package auth

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"chaos.awaits.us/api/config"
	"github.com/resend/resend-go/v2"
)

const (
	tokenExpiry   = 15 * time.Minute
	sessionExpiry = 180 * 24 * time.Hour
	cookieName    = "session"
)

type tokenFile struct {
	Email  string    `json:"email"`
	Expiry time.Time `json:"expiry"`
}

type sessionFile struct {
	Email   string    `json:"email"`
	Role    string    `json:"role"`
	Created time.Time `json:"created"`
}

// contextKey is an unexported type for context keys in this package.
type contextKey int

const emailKey contextKey = 0
const roleKey contextKey = 1

// EmailFromContext returns the authenticated email from the request context.
func EmailFromContext(ctx context.Context) string {
	v, _ := ctx.Value(emailKey).(string)
	return v
}

// RoleFromContext returns the role ("view" or "post") from the request context.
func RoleFromContext(ctx context.Context) string {
	v, _ := ctx.Value(roleKey).(string)
	return v
}

func generateHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func saveToken(authDir, token, email string) error {
	dir := filepath.Join(authDir, "tokens")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	data, err := json.Marshal(tokenFile{Email: email, Expiry: time.Now().Add(tokenExpiry)})
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, token), data, 0o600)
}

func validateToken(authDir, token string) (string, error) {
	path := filepath.Join(authDir, "tokens", token)
	data, err := os.ReadFile(path)
	os.Remove(path) // single-use: always delete
	if err != nil {
		return "", fmt.Errorf("invalid token")
	}
	var tf tokenFile
	if err := json.Unmarshal(data, &tf); err != nil {
		return "", fmt.Errorf("invalid token")
	}
	if time.Now().After(tf.Expiry) {
		return "", fmt.Errorf("token expired")
	}
	return tf.Email, nil
}

func createSession(authDir, email, role string) (string, error) {
	dir := filepath.Join(authDir, "sessions")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	id, err := generateHex(32)
	if err != nil {
		return "", err
	}
	data, err := json.Marshal(sessionFile{Email: email, Role: role, Created: time.Now()})
	if err != nil {
		return "", err
	}
	return id, os.WriteFile(filepath.Join(dir, id), data, 0o600)
}

func validateSession(authDir, sessionID string) (string, string, error) {
	path := filepath.Join(authDir, "sessions", sessionID)
	data, err := os.ReadFile(path)
	if err != nil {
		return "", "", fmt.Errorf("invalid session")
	}
	var sf sessionFile
	if err := json.Unmarshal(data, &sf); err != nil {
		return "", "", fmt.Errorf("invalid session")
	}
	if time.Since(sf.Created) > sessionExpiry {
		os.Remove(path)
		return "", "", fmt.Errorf("session expired")
	}
	return sf.Email, sf.Role, nil
}

// emailInCSV checks if an email exists in a CSV file (one email per line, case-insensitive).
func emailInCSV(path, email string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		// First column is the email; ignore any subsequent columns.
		field, _, _ := strings.Cut(line, ",")
		if strings.EqualFold(strings.TrimSpace(field), email) {
			return true
		}
	}
	return false
}

// appendToCSV appends an email to a CSV file on a new line.
func appendToCSV(path, email string) error {
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = fmt.Fprintln(f, email)
	return err
}

// lookupRole returns the role for an email, or "" if not authorized.
// CSV files are read from configDir (alongside config.yaml), not authDir.
func lookupRole(configDir, email string) string {
	if emailInCSV(filepath.Join(configDir, "can-post.csv"), email) {
		return "post"
	}
	if emailInCSV(filepath.Join(configDir, "can-view.csv"), email) {
		return "view"
	}
	return ""
}

// LoginPage serves the login form.
func LoginPage() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		if r.URL.Query().Has("sent") {
			fmt.Fprint(w, loginSentHTML)
		} else {
			fmt.Fprint(w, loginFormHTML)
		}
	}
}

// SendLink handles the login form submission.
func SendLink(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			http.Redirect(w, r, "/auth/login", http.StatusSeeOther)
			return
		}
		email := strings.TrimSpace(strings.ToLower(r.FormValue("email")))
		if email == "" {
			http.Redirect(w, r, "/auth/login", http.StatusSeeOther)
			return
		}

		role := lookupRole(cfg.Dir, email)
		if role != "" {
			// Authorized: send magic link(s).
			siteToken, err := generateHex(32)
			if err != nil {
				log.Printf("auth: generate token: %v", err)
				http.Error(w, "Internal error", http.StatusInternalServerError)
				return
			}
			if err := saveToken(cfg.AuthDir(), siteToken, email); err != nil {
				log.Printf("auth: save token: %v", err)
				http.Error(w, "Internal error", http.StatusInternalServerError)
				return
			}

			// Post-role users get a separate token for the app deep link.
			appToken := ""
			if role == "post" {
				appToken, err = generateHex(32)
				if err != nil {
					log.Printf("auth: generate app token: %v", err)
					http.Error(w, "Internal error", http.StatusInternalServerError)
					return
				}
				if err := saveToken(cfg.AuthDir(), appToken, email); err != nil {
					log.Printf("auth: save app token: %v", err)
					http.Error(w, "Internal error", http.StatusInternalServerError)
					return
				}
			}

			if err := sendMagicLink(cfg, email, siteToken, appToken, role); err != nil {
				log.Printf("auth: send email to %s: %v", email, err)
				// Still redirect so we don't leak info.
			}
		} else {
			// Not authorized: record request, send polite email.
			if err := appendToCSV(filepath.Join(cfg.Dir, "wants-account.csv"), email); err != nil {
				log.Printf("auth: append to wants-account: %v", err)
			}
			if err := sendRequestRecorded(cfg, email); err != nil {
				log.Printf("auth: send request-recorded email to %s: %v", email, err)
			}
		}

		http.Redirect(w, r, "/auth/login?sent=1", http.StatusSeeOther)
	}
}

// Verify handles the magic link click.
// For browsers: sets a session cookie and redirects to /.
// For API clients (Accept: application/json): returns JSON with session ID.
func Verify(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := r.URL.Query().Get("token")
		wantsJSON := strings.Contains(r.Header.Get("Accept"), "application/json")

		email, err := validateToken(cfg.AuthDir(), token)
		if err != nil {
			log.Printf("auth: verify: %v", err)
			if wantsJSON {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusUnauthorized)
				fmt.Fprint(w, `{"error":"invalid or expired token"}`)
			} else {
				http.Redirect(w, r, "/auth/login", http.StatusSeeOther)
			}
			return
		}

		role := lookupRole(cfg.Dir, email)
		if role == "" {
			if wantsJSON {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusForbidden)
				fmt.Fprint(w, `{"error":"not authorized"}`)
			} else {
				http.Redirect(w, r, "/auth/login", http.StatusSeeOther)
			}
			return
		}

		sessionID, err := createSession(cfg.AuthDir(), email, role)
		if err != nil {
			log.Printf("auth: create session: %v", err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}

		if wantsJSON {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]string{
				"session": sessionID,
				"role":    role,
			})
			return
		}

		secure := strings.HasPrefix(cfg.BaseURL(), "https")
		http.SetCookie(w, &http.Cookie{
			Name:     cookieName,
			Value:    sessionID,
			Path:     "/",
			MaxAge:   int(sessionExpiry.Seconds()),
			HttpOnly: true,
			SameSite: http.SameSiteLaxMode,
			Secure:   secure,
		})
		http.Redirect(w, r, "/", http.StatusSeeOther)
	}
}

// Middleware protects routes behind auth.
// /health and /auth/* pass through. /files/ requires "post" role.
func Middleware(cfg *config.Config, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path

		// Public routes.
		if path == "/health" || strings.HasPrefix(path, "/auth/") {
			next.ServeHTTP(w, r)
			return
		}

		// Accept session from cookie or Authorization: Bearer header.
		var sessionID string
		if auth := r.Header.Get("Authorization"); strings.HasPrefix(auth, "Bearer ") {
			sessionID = strings.TrimPrefix(auth, "Bearer ")
		} else if cookie, err := r.Cookie(cookieName); err == nil {
			sessionID = cookie.Value
		}
		if sessionID == "" {
			log.Printf("auth: denied %s %s (no session)", r.Method, path)
			authDenied(w, r)
			return
		}

		email, role, err := validateSession(cfg.AuthDir(), sessionID)
		if err != nil {
			log.Printf("auth: denied %s %s (%v)", r.Method, path, err)
			authDenied(w, r)
			return
		}

		// /files/ requires post role.
		if strings.HasPrefix(path, "/files") && role != "post" {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}

		ctx := context.WithValue(r.Context(), emailKey, email)
		ctx = context.WithValue(ctx, roleKey, role)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func authDenied(w http.ResponseWriter, r *http.Request) {
	if strings.Contains(r.Header.Get("Accept"), "text/html") {
		http.Redirect(w, r, "/auth/login", http.StatusSeeOther)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	fmt.Fprint(w, `{"error":"unauthorized"}`)
}

func sendMagicLink(cfg *config.Config, email, siteToken, appToken, role string) error {
	siteLink := cfg.BaseURL() + "/auth/verify?token=" + siteToken

	var html string
	if role == "post" && appToken != "" {
		appLink := "chaos://auth?token=" + appToken + "&server=" + cfg.BaseURL()
		html = fmt.Sprintf(`<p>Click to log in:</p>
<p><a href="%s">Log in to the site</a></p>
<p><a href="%s">Log in to the app</a></p>
<p>These links expire in 15 minutes.</p>`, siteLink, appLink)
	} else {
		html = fmt.Sprintf(`<p>Click to log in:</p>
<p><a href="%s">Log in to chaos.awaits.us</a></p>
<p>This link expires in 15 minutes.</p>`, siteLink)
	}

	client := resend.NewClient(cfg.ResendAPIKey())
	_, err := client.Emails.Send(&resend.SendEmailRequest{
		From:    cfg.FromEmail(),
		To:      []string{email},
		Subject: "Your login link",
		Html:    html,
	})
	return err
}

func sendRequestRecorded(cfg *config.Config, email string) error {
	client := resend.NewClient(cfg.ResendAPIKey())
	_, err := client.Emails.Send(&resend.SendEmailRequest{
		From:    cfg.FromEmail(),
		To:      []string{email},
		Subject: "Account request received",
		Html:    "<p>We've recorded your request for an account. You'll hear back soon.</p>",
	})
	return err
}

const loginFormHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Login — chaos.awaits.us</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
display:flex;align-items:center;justify-content:center;min-height:100vh;
background:#fafafa;color:#262626}
@media(prefers-color-scheme:dark){body{background:#000;color:#f5f5f5}}
.card{max-width:340px;width:100%;padding:32px;text-align:center}
h1{font-size:20px;margin-bottom:24px;letter-spacing:-0.02em}
input[type=email]{width:100%;padding:10px 12px;border:1px solid #dbdbdb;border-radius:6px;
font-size:14px;margin-bottom:12px;background:inherit;color:inherit}
@media(prefers-color-scheme:dark){input[type=email]{border-color:#363636}}
button{width:100%;padding:10px;border:none;border-radius:6px;
background:#262626;color:#fff;font-size:14px;font-weight:600;cursor:pointer}
@media(prefers-color-scheme:dark){button{background:#f5f5f5;color:#000}}
</style>
</head>
<body>
<div class="card">
<h1>chaos.awaits.us</h1>
<form method="POST" action="/auth/send">
<input type="email" name="email" placeholder="your@email.com" required autofocus>
<button type="submit">Send Login Link</button>
</form>
</div>
</body>
</html>`

const loginSentHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Check your email — chaos.awaits.us</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
display:flex;align-items:center;justify-content:center;min-height:100vh;
background:#fafafa;color:#262626}
@media(prefers-color-scheme:dark){body{background:#000;color:#f5f5f5}}
.card{max-width:340px;width:100%;padding:32px;text-align:center}
h1{font-size:20px;margin-bottom:12px;letter-spacing:-0.02em}
p{font-size:14px;color:#8e8e8e;line-height:1.5}
</style>
</head>
<body>
<div class="card">
<h1>Check your email</h1>
<p>If your address is recognised, you'll receive a login link shortly.</p>
</div>
</body>
</html>`
