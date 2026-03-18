package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jphastings/cosy-posts/api/auth"
	"github.com/jphastings/cosy-posts/api/config"
	"github.com/jphastings/cosy-posts/api/info"
	"github.com/jphastings/cosy-posts/api/post"
	"github.com/jphastings/cosy-posts/api/upload"

	tusd "github.com/tus/tusd/v2/pkg/handler"
)

// testServer holds a fully wired test server matching the production routes.
type testServer struct {
	server    *httptest.Server
	cfg       *config.Config
	sessionID string
}

// newTestServer creates a test server with real handlers, temp directories,
// and a pre-authenticated session with the "post" role.
func newTestServer(t *testing.T) *testServer {
	t.Helper()

	contentDir := t.TempDir()
	authDir := t.TempDir()

	// Create required auth CSV files.
	if err := os.WriteFile(filepath.Join(authDir, "can-post.csv"), []byte("test@example.com\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(authDir, "can-view.csv"), []byte("viewer@example.com\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	uploadDir := t.TempDir()

	cfg := &config.Config{
		Listen:     ":0",
		ContentDir: contentDir,
		AuthDir:    authDir,
		UploadDir:  uploadDir,
	}
	cfg.Site.Name = "Test Site"
	cfg.Email.From = "test@example.com"
	cfg.Email.ResendAPIKey = "re_test_fake"

	// No-op body completion (don't assemble posts in contract tests).
	onBodyDone := func(event tusd.HookEvent) {}

	uploadHandler, err := upload.NewHandler(cfg, onBodyDone)
	if err != nil {
		t.Fatal(err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})
	mux.HandleFunc("GET /api/info", info.Handler(cfg))
	mux.Handle("/files/", http.StripPrefix("/files/", uploadHandler))
	mux.Handle("/files", http.StripPrefix("/files", uploadHandler))
	mux.HandleFunc("GET /auth/login", auth.LoginPage(cfg))
	mux.HandleFunc("POST /auth/send", auth.SendLink(cfg))
	mux.HandleFunc("GET /auth/verify", auth.Verify(cfg))
	mux.HandleFunc("DELETE /api/posts/{id}", post.DeleteHandler(cfg))
	mux.HandleFunc("GET /api/access-requests", auth.ListAccessRequests(cfg))
	mux.HandleFunc("POST /api/access-requests/{email}/approve", auth.ApproveAccessRequest(cfg))
	mux.HandleFunc("DELETE /api/access-requests/{email}", auth.DenyAccessRequest(cfg))

	handler := auth.Middleware(cfg, mux)
	server := httptest.NewServer(handler)

	// Create a session directly (bypassing email flow).
	sessionID := createTestSession(t, authDir, "test@example.com", "post")

	return &testServer{
		server:    server,
		cfg:       cfg,
		sessionID: sessionID,
	}
}

// createTestSession writes a session file directly to the auth directory.
func createTestSession(t *testing.T, authDir, email, role string) string {
	t.Helper()
	sessDir := filepath.Join(authDir, "sessions")
	if err := os.MkdirAll(sessDir, 0o755); err != nil {
		t.Fatal(err)
	}
	// Use a fixed 64-char hex string for determinism.
	sessionID := "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
	data := fmt.Sprintf(`{"email":%q,"role":%q,"created":%q}`, email, role, time.Now().Format(time.RFC3339))
	if err := os.WriteFile(filepath.Join(sessDir, sessionID), []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}
	return sessionID
}

func (ts *testServer) close() {
	ts.server.Close()
}

// do performs an HTTP request against the test server.
func (ts *testServer) do(req *http.Request) *http.Response {
	resp, err := ts.server.Client().Do(req)
	if err != nil {
		panic(fmt.Sprintf("request failed: %v", err))
	}
	return resp
}

// encodeTUSMetadata encodes metadata the way the iOS app does:
// "key base64(value)" pairs joined by commas.
func encodeTUSMetadata(meta map[string]string) string {
	var pairs []string
	for k, v := range meta {
		encoded := base64.StdEncoding.EncodeToString([]byte(v))
		pairs = append(pairs, k+" "+encoded)
	}
	return strings.Join(pairs, ",")
}

// =============================================================================
// Contract: Auth Middleware (contracts/auth_middleware.json)
// =============================================================================

func TestContract_AuthMiddleware_PublicRoutes(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// Health endpoint must be accessible without auth.
	req, _ := http.NewRequest("GET", ts.server.URL+"/health", nil)
	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("GET /health: expected 200, got %d", resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "ok" {
		t.Fatalf("GET /health: expected 'ok', got %q", body)
	}
}

func TestContract_AuthMiddleware_BearerToken(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// Authenticated request with Bearer token (as the app sends).
	req, _ := http.NewRequest("GET", ts.server.URL+"/api/info", nil)
	req.Header.Set("Authorization", "Bearer "+ts.sessionID)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("GET /api/info with Bearer: expected 200, got %d", resp.StatusCode)
	}
}

func TestContract_AuthMiddleware_Unauthorized(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// Request without auth to a protected endpoint.
	req, _ := http.NewRequest("GET", ts.server.URL+"/api/info", nil)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 401 {
		t.Fatalf("GET /api/info without auth: expected 401, got %d", resp.StatusCode)
	}

	// App expects JSON error response.
	var errResp map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&errResp); err != nil {
		t.Fatalf("expected JSON error body: %v", err)
	}
	if errResp["error"] != "unauthorized" {
		t.Fatalf("expected error='unauthorized', got %q", errResp["error"])
	}
}

// =============================================================================
// Contract: Auth Verify (contracts/auth_verify.json)
// =============================================================================

func TestContract_AuthVerify_Success(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// Create a token for verification.
	token := "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
	tokenData := fmt.Sprintf(`{"email":"test@example.com","expiry":%q}`, time.Now().Add(15*time.Minute).Format(time.RFC3339))
	tokDir := filepath.Join(ts.cfg.AuthDir, "tokens")
	os.MkdirAll(tokDir, 0o755)
	os.WriteFile(filepath.Join(tokDir, token), []byte(tokenData), 0o600)

	// App sends GET /auth/verify?token=... with Accept: application/json
	req, _ := http.NewRequest("GET", ts.server.URL+"/auth/verify?token="+token, nil)
	req.Header.Set("Accept", "application/json")

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("GET /auth/verify: expected 200, got %d (body: %s)", resp.StatusCode, body)
	}

	// App decodes: { "session": string, "role": string, "email": string }
	var result map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode verify response: %v", err)
	}

	if result["session"] == "" {
		t.Fatal("verify response missing 'session' field")
	}
	if result["role"] == "" {
		t.Fatal("verify response missing 'role' field")
	}
	if result["email"] == "" {
		t.Fatal("verify response missing 'email' field")
	}
	if result["email"] != "test@example.com" {
		t.Fatalf("expected email='test@example.com', got %q", result["email"])
	}
	if result["role"] != "post" {
		t.Fatalf("expected role='post', got %q", result["role"])
	}
	// Session ID must be 64-char hex.
	if len(result["session"]) != 64 {
		t.Fatalf("session ID should be 64 hex chars, got %d chars", len(result["session"]))
	}
}

func TestContract_AuthVerify_InvalidToken(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	req, _ := http.NewRequest("GET", ts.server.URL+"/auth/verify?token=0000000000000000000000000000000000000000000000000000000000000000", nil)
	req.Header.Set("Accept", "application/json")

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 401 {
		t.Fatalf("verify with invalid token: expected 401, got %d", resp.StatusCode)
	}
}

// =============================================================================
// Contract: Auth Send (contracts/auth_send.json)
// =============================================================================

func TestContract_AuthSend_FormEncoded(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// App sends POST /auth/send with form-encoded email and Accept: application/json.
	form := url.Values{"email": {"test@example.com"}}
	req, _ := http.NewRequest("POST", ts.server.URL+"/auth/send", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("POST /auth/send: expected 200, got %d (body: %s)", resp.StatusCode, body)
	}

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode auth/send response: %v", err)
	}
	if result["ok"] != true {
		t.Fatalf("expected ok=true, got %v", result["ok"])
	}
}

// =============================================================================
// Contract: Info (contracts/info.json)
// =============================================================================

func TestContract_Info_ResponseShape(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// App sends GET /api/info with Bearer token.
	req, _ := http.NewRequest("GET", ts.server.URL+"/api/info", nil)
	req.Header.Set("Authorization", "Bearer "+ts.sessionID)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("GET /api/info: expected 200, got %d", resp.StatusCode)
	}

	ct := resp.Header.Get("Content-Type")
	if !strings.HasPrefix(ct, "application/json") {
		t.Fatalf("expected Content-Type application/json, got %q", ct)
	}

	// App decodes into SiteInfo with these exact JSON keys.
	var result map[string]json.RawMessage
	body, _ := io.ReadAll(resp.Body)
	if err := json.Unmarshal(body, &result); err != nil {
		t.Fatalf("failed to decode info response: %v", err)
	}

	// Verify all required top-level keys exist (matching Swift SiteInfo struct).
	requiredKeys := []string{"name", "version", "git_sha", "stats", "locales"}
	for _, key := range requiredKeys {
		if _, ok := result[key]; !ok {
			t.Errorf("info response missing required key %q", key)
		}
	}

	// Verify stats sub-object has the required keys (matching Swift SiteStats struct).
	var stats map[string]json.RawMessage
	if err := json.Unmarshal(result["stats"], &stats); err != nil {
		t.Fatalf("failed to decode stats: %v", err)
	}
	statsKeys := []string{"posts", "photos", "videos", "audio", "members"}
	for _, key := range statsKeys {
		if _, ok := stats[key]; !ok {
			t.Errorf("stats missing required key %q", key)
		}
	}

	// Verify locales is an array (may be empty).
	var locales []string
	if err := json.Unmarshal(result["locales"], &locales); err != nil {
		t.Fatalf("locales should be a string array: %v", err)
	}
}

// =============================================================================
// Contract: TUS Upload — Media (contracts/tus_upload_media.json)
// =============================================================================

func TestContract_TUSUpload_Media(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// App sends POST /files/ with TUS headers and metadata matching the contract.
	metadata := map[string]string{
		"post-id":      "abc123def456ghi789jkl",
		"filename":     "media_0.jpg",
		"content-type": "image/jpeg",
		"author":       "test@example.com",
	}

	req, _ := http.NewRequest("POST", ts.server.URL+"/files/", nil)
	req.Header.Set("Tus-Resumable", "1.0.0")
	req.Header.Set("Upload-Length", "1024")
	req.Header.Set("Upload-Metadata", encodeTUSMetadata(metadata))
	req.Header.Set("Authorization", "Bearer "+ts.sessionID)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("TUS create media: expected 201, got %d (body: %s)", resp.StatusCode, body)
	}

	location := resp.Header.Get("Location")
	if location == "" {
		t.Fatal("TUS create media: missing Location header")
	}
}

// =============================================================================
// Contract: TUS Upload — Body (contracts/tus_upload_body.json)
// =============================================================================

func TestContract_TUSUpload_Body(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// App sends body upload with specific metadata keys.
	metadata := map[string]string{
		"post-id":      "abc123def456ghi789jkl",
		"filename":     "body",
		"content-type": "text/plain",
		"role":         "body",
		"date":         "2026-03-18T12:34:56Z",
		"locale":       "en",
		"content-ext":  "md",
		"author":       "test@example.com",
	}

	req, _ := http.NewRequest("POST", ts.server.URL+"/files/", nil)
	req.Header.Set("Tus-Resumable", "1.0.0")
	req.Header.Set("Upload-Length", "13")
	req.Header.Set("Upload-Metadata", encodeTUSMetadata(metadata))
	req.Header.Set("Authorization", "Bearer "+ts.sessionID)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("TUS create body: expected 201, got %d (body: %s)", resp.StatusCode, body)
	}

	location := resp.Header.Get("Location")
	if location == "" {
		t.Fatal("TUS create body: missing Location header")
	}
}

// =============================================================================
// Contract: TUS Upload — Locale Body (contracts/tus_upload_body_locale.json)
// =============================================================================

func TestContract_TUSUpload_BodyLocale(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	metadata := map[string]string{
		"post-id":      "abc123def456ghi789jkl",
		"filename":     "body-es",
		"content-type": "text/plain",
		"role":         "body-locale",
		"locale":       "es",
		"content-ext":  "md",
		"author":       "test@example.com",
	}

	req, _ := http.NewRequest("POST", ts.server.URL+"/files/", nil)
	req.Header.Set("Tus-Resumable", "1.0.0")
	req.Header.Set("Upload-Length", "20")
	req.Header.Set("Upload-Metadata", encodeTUSMetadata(metadata))
	req.Header.Set("Authorization", "Bearer "+ts.sessionID)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("TUS create body-locale: expected 201, got %d (body: %s)", resp.StatusCode, body)
	}
}

// =============================================================================
// Contract: TUS Upload Data PATCH (contracts/tus_upload_data.json)
// =============================================================================

func TestContract_TUSUpload_PatchData(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// First, create an upload.
	metadata := map[string]string{
		"post-id":      "abc123def456ghi789jkl",
		"filename":     "media_0.jpg",
		"content-type": "image/jpeg",
	}

	createReq, _ := http.NewRequest("POST", ts.server.URL+"/files/", nil)
	createReq.Header.Set("Tus-Resumable", "1.0.0")
	createReq.Header.Set("Upload-Length", "5")
	createReq.Header.Set("Upload-Metadata", encodeTUSMetadata(metadata))
	createReq.Header.Set("Authorization", "Bearer "+ts.sessionID)

	createResp := ts.do(createReq)
	createResp.Body.Close()

	if createResp.StatusCode != 201 {
		t.Fatalf("TUS create for PATCH test: expected 201, got %d", createResp.StatusCode)
	}

	location := createResp.Header.Get("Location")

	// Resolve the Location (may be relative) against the server URL.
	uploadURL, err := url.Parse(location)
	if err != nil {
		t.Fatalf("invalid Location header: %v", err)
	}
	base, _ := url.Parse(ts.server.URL + "/files/")
	resolved := base.ResolveReference(uploadURL)

	// Now PATCH with data — exactly as the app's TUSClient does.
	data := []byte("hello")
	patchReq, _ := http.NewRequest("PATCH", resolved.String(), bytes.NewReader(data))
	patchReq.Header.Set("Tus-Resumable", "1.0.0")
	patchReq.Header.Set("Upload-Offset", "0")
	patchReq.Header.Set("Content-Type", "application/offset+octet-stream")
	patchReq.Header.Set("Authorization", "Bearer "+ts.sessionID)

	patchResp := ts.do(patchReq)
	defer patchResp.Body.Close()

	if patchResp.StatusCode != 204 {
		body, _ := io.ReadAll(patchResp.Body)
		t.Fatalf("TUS PATCH: expected 204, got %d (body: %s)", patchResp.StatusCode, body)
	}

	newOffset := patchResp.Header.Get("Upload-Offset")
	if newOffset != "5" {
		t.Fatalf("TUS PATCH: expected Upload-Offset=5, got %q", newOffset)
	}
}

// =============================================================================
// Contract: TUS HEAD — Get Offset (used for resume)
// =============================================================================

func TestContract_TUSUpload_HeadOffset(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// Create an upload.
	metadata := map[string]string{
		"post-id":      "abc123def456ghi789jkl",
		"filename":     "media_1.png",
		"content-type": "image/png",
	}

	createReq, _ := http.NewRequest("POST", ts.server.URL+"/files/", nil)
	createReq.Header.Set("Tus-Resumable", "1.0.0")
	createReq.Header.Set("Upload-Length", "100")
	createReq.Header.Set("Upload-Metadata", encodeTUSMetadata(metadata))
	createReq.Header.Set("Authorization", "Bearer "+ts.sessionID)

	createResp := ts.do(createReq)
	createResp.Body.Close()

	location := createResp.Header.Get("Location")
	base, _ := url.Parse(ts.server.URL + "/files/")
	uploadURL, _ := url.Parse(location)
	resolved := base.ResolveReference(uploadURL)

	// HEAD to get offset (as app does for resume).
	headReq, _ := http.NewRequest("HEAD", resolved.String(), nil)
	headReq.Header.Set("Tus-Resumable", "1.0.0")
	headReq.Header.Set("Authorization", "Bearer "+ts.sessionID)

	headResp := ts.do(headReq)
	defer headResp.Body.Close()

	if headResp.StatusCode != 200 {
		t.Fatalf("TUS HEAD: expected 200, got %d", headResp.StatusCode)
	}

	offset := headResp.Header.Get("Upload-Offset")
	if offset != "0" {
		t.Fatalf("TUS HEAD: expected Upload-Offset=0 for new upload, got %q", offset)
	}
}

// =============================================================================
// Contract: Access Requests (contracts/access_requests.json)
// =============================================================================

func TestContract_AccessRequests_List(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// App sends GET /api/access-requests with Bearer token.
	req, _ := http.NewRequest("GET", ts.server.URL+"/api/access-requests", nil)
	req.Header.Set("Authorization", "Bearer "+ts.sessionID)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("list access requests: expected 200, got %d", resp.StatusCode)
	}

	// App decodes as [String] (JSON array of email strings).
	var emails []string
	if err := json.NewDecoder(resp.Body).Decode(&emails); err != nil {
		t.Fatalf("expected JSON array of strings: %v", err)
	}
}

func TestContract_AccessRequests_Approve(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// Seed a wants-account.csv entry.
	wantsPath := filepath.Join(ts.cfg.AuthDir, "wants-account.csv")
	os.WriteFile(wantsPath, []byte("newuser@example.com\n"), 0o644)

	// App sends POST /api/access-requests/{email}/approve.
	req, _ := http.NewRequest("POST", ts.server.URL+"/api/access-requests/newuser@example.com/approve", nil)
	req.Header.Set("Authorization", "Bearer "+ts.sessionID)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("approve: expected 200, got %d (body: %s)", resp.StatusCode, body)
	}

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode approve response: %v", err)
	}
	if result["ok"] != true {
		t.Fatalf("expected ok=true, got %v", result["ok"])
	}
}

func TestContract_AccessRequests_Deny(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// Seed a wants-account.csv entry.
	wantsPath := filepath.Join(ts.cfg.AuthDir, "wants-account.csv")
	os.WriteFile(wantsPath, []byte("reject@example.com\n"), 0o644)

	// App sends DELETE /api/access-requests/{email}.
	req, _ := http.NewRequest("DELETE", ts.server.URL+"/api/access-requests/reject@example.com", nil)
	req.Header.Set("Authorization", "Bearer "+ts.sessionID)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("deny: expected 200, got %d (body: %s)", resp.StatusCode, body)
	}

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode deny response: %v", err)
	}
	if result["ok"] != true {
		t.Fatalf("expected ok=true, got %v", result["ok"])
	}
}

// =============================================================================
// Contract: Delete Post (contracts/delete_post.json)
// =============================================================================

func TestContract_DeletePost(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// Create a fake post directory with an index file.
	postID := "testpost123testpost12"
	postDir := filepath.Join(ts.cfg.ContentDir, "2026", "03", "18", postID)
	os.MkdirAll(postDir, 0o755)
	os.WriteFile(filepath.Join(postDir, "index.md"), []byte("---\ndate: 2026-03-18\n---\nHello"), 0o644)

	// App sends DELETE /api/posts/{id} with Bearer token.
	req, _ := http.NewRequest("DELETE", ts.server.URL+"/api/posts/"+postID, nil)
	req.Header.Set("Authorization", "Bearer "+ts.sessionID)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("delete post: expected 200, got %d (body: %s)", resp.StatusCode, body)
	}

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode delete response: %v", err)
	}
	if result["ok"] != true {
		t.Fatalf("expected ok=true, got %v", result["ok"])
	}

	// Verify post directory was removed.
	if _, err := os.Stat(postDir); !os.IsNotExist(err) {
		t.Fatal("post directory should have been deleted")
	}
}

func TestContract_DeletePost_NotFound(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	req, _ := http.NewRequest("DELETE", ts.server.URL+"/api/posts/nonexistent123456789", nil)
	req.Header.Set("Authorization", "Bearer "+ts.sessionID)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 404 {
		t.Fatalf("delete non-existent post: expected 404, got %d", resp.StatusCode)
	}
}

// =============================================================================
// Contract: TUS requires auth with "post" role
// =============================================================================

func TestContract_TUS_RequiresPostRole(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	// Create a view-only session.
	viewSessionID := createTestSession(t, ts.cfg.AuthDir, "viewer@example.com", "view")

	req, _ := http.NewRequest("POST", ts.server.URL+"/files/", nil)
	req.Header.Set("Tus-Resumable", "1.0.0")
	req.Header.Set("Upload-Length", "100")
	req.Header.Set("Upload-Metadata", encodeTUSMetadata(map[string]string{
		"post-id":      "abc123def456ghi789jkl",
		"filename":     "test.jpg",
		"content-type": "image/jpeg",
	}))
	req.Header.Set("Authorization", "Bearer "+viewSessionID)

	resp := ts.do(req)
	defer resp.Body.Close()

	if resp.StatusCode != 403 {
		t.Fatalf("TUS with view role: expected 403, got %d", resp.StatusCode)
	}
}

// =============================================================================
// Contract: Full upload flow (end-to-end: create → PATCH → complete)
// This mirrors the exact sequence the app performs.
// =============================================================================

func TestContract_FullUploadFlow(t *testing.T) {
	ts := newTestServer(t)
	defer ts.close()

	postID := "e2etestpost000000000"

	// Step 1: Upload media file (as app does).
	mediaData := []byte("fake-jpeg-data")
	mediaMetadata := map[string]string{
		"post-id":      postID,
		"filename":     "media_0.jpg",
		"content-type": "image/jpeg",
		"author":       "test@example.com",
	}

	createReq, _ := http.NewRequest("POST", ts.server.URL+"/files/", nil)
	createReq.Header.Set("Tus-Resumable", "1.0.0")
	createReq.Header.Set("Upload-Length", fmt.Sprintf("%d", len(mediaData)))
	createReq.Header.Set("Upload-Metadata", encodeTUSMetadata(mediaMetadata))
	createReq.Header.Set("Authorization", "Bearer "+ts.sessionID)

	createResp := ts.do(createReq)
	createResp.Body.Close()
	if createResp.StatusCode != 201 {
		t.Fatalf("create media upload: expected 201, got %d", createResp.StatusCode)
	}

	mediaLocation := createResp.Header.Get("Location")
	base, _ := url.Parse(ts.server.URL + "/files/")
	mediaURL, _ := url.Parse(mediaLocation)
	resolvedMedia := base.ResolveReference(mediaURL)

	// Step 2: PATCH media data.
	patchReq, _ := http.NewRequest("PATCH", resolvedMedia.String(), bytes.NewReader(mediaData))
	patchReq.Header.Set("Tus-Resumable", "1.0.0")
	patchReq.Header.Set("Upload-Offset", "0")
	patchReq.Header.Set("Content-Type", "application/offset+octet-stream")
	patchReq.Header.Set("Authorization", "Bearer "+ts.sessionID)

	patchResp := ts.do(patchReq)
	patchResp.Body.Close()
	if patchResp.StatusCode != 204 {
		t.Fatalf("PATCH media: expected 204, got %d", patchResp.StatusCode)
	}

	// Step 3: Upload body (last, triggers assembly on server).
	bodyText := []byte("Hello world! #sunset #travel")
	bodyMetadata := map[string]string{
		"post-id":      postID,
		"filename":     "body",
		"content-type": "text/plain",
		"role":         "body",
		"date":         "2026-03-18T12:34:56Z",
		"locale":       "en",
		"content-ext":  "md",
		"author":       "test@example.com",
	}

	bodyCreateReq, _ := http.NewRequest("POST", ts.server.URL+"/files/", nil)
	bodyCreateReq.Header.Set("Tus-Resumable", "1.0.0")
	bodyCreateReq.Header.Set("Upload-Length", fmt.Sprintf("%d", len(bodyText)))
	bodyCreateReq.Header.Set("Upload-Metadata", encodeTUSMetadata(bodyMetadata))
	bodyCreateReq.Header.Set("Authorization", "Bearer "+ts.sessionID)

	bodyCreateResp := ts.do(bodyCreateReq)
	bodyCreateResp.Body.Close()
	if bodyCreateResp.StatusCode != 201 {
		t.Fatalf("create body upload: expected 201, got %d", bodyCreateResp.StatusCode)
	}

	bodyLocation := bodyCreateResp.Header.Get("Location")
	bodyURL, _ := url.Parse(bodyLocation)
	resolvedBody := base.ResolveReference(bodyURL)

	bodyPatchReq, _ := http.NewRequest("PATCH", resolvedBody.String(), bytes.NewReader(bodyText))
	bodyPatchReq.Header.Set("Tus-Resumable", "1.0.0")
	bodyPatchReq.Header.Set("Upload-Offset", "0")
	bodyPatchReq.Header.Set("Content-Type", "application/offset+octet-stream")
	bodyPatchReq.Header.Set("Authorization", "Bearer "+ts.sessionID)

	bodyPatchResp := ts.do(bodyPatchReq)
	bodyPatchResp.Body.Close()
	if bodyPatchResp.StatusCode != 204 {
		t.Fatalf("PATCH body: expected 204, got %d", bodyPatchResp.StatusCode)
	}
}
