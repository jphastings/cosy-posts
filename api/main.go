package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/jphastings/cosy-posts/api/auth"
	"github.com/jphastings/cosy-posts/api/config"
	"github.com/jphastings/cosy-posts/api/info"
	"github.com/jphastings/cosy-posts/api/post"
	"github.com/jphastings/cosy-posts/api/rebuild"
	"github.com/jphastings/cosy-posts/api/site"
	"github.com/jphastings/cosy-posts/api/upload"
	flag "github.com/spf13/pflag"

	tusd "github.com/tus/tusd/v2/pkg/handler"
)

func main() {
	configPath := flag.String("config", "", "path to YAML config file")
	flag.Parse()

	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Validate auth CSV files exist.
	if err := auth.ValidateAuthFiles(cfg.AuthDir); err != nil {
		log.Fatalf("Auth configuration error: %v", err)
	}

	// Ensure required directories exist.
	for _, dir := range []string{cfg.ContentDir, cfg.TUSUploadDir(), cfg.AuthDir} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			log.Fatalf("Failed to create directory %s: %v", dir, err)
		}
	}
	if cfg.HasExternalSite() {
		if err := os.MkdirAll(cfg.SiteDir(), 0o755); err != nil {
			log.Fatalf("Failed to create directory %s: %v", cfg.SiteDir(), err)
		}
	}

	// Body upload completion triggers post assembly.
	onBodyDone := func(event tusd.HookEvent) {
		postID := event.Upload.MetaData["post-id"]
		log.Printf("Body upload completed for post %s, starting assembly", postID)

		if err := post.Assemble(cfg, event); err != nil {
			log.Printf("Error assembling post %s: %v", postID, err)
			return
		}

		// Trigger site rebuild in the background (only if external build configured).
		rebuild.Trigger(cfg)
	}

	uploadHandler, err := upload.NewHandler(cfg, onBodyDone)
	if err != nil {
		log.Fatalf("Failed to create upload handler: %v", err)
	}

	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	mux.HandleFunc("GET /api/info", info.Handler(cfg))
	mux.HandleFunc("GET /api/info/site", info.SiteInfoHandler(cfg))

	// Mount TUS upload handler at /files/.
	mux.Handle("/files/", http.StripPrefix("/files/", uploadHandler))
	mux.Handle("/files", http.StripPrefix("/files", uploadHandler))

	// Auth routes.
	mux.HandleFunc("GET /auth/login", auth.LoginPage(cfg))
	mux.HandleFunc("POST /auth/send", auth.SendLink(cfg))
	mux.HandleFunc("GET /auth/verify", auth.Verify(cfg))

	// Delete post endpoint (requires "post" role).
	mux.HandleFunc("DELETE /api/posts/{id}", post.DeleteHandler(cfg))

	// Access request management (requires "post" role).
	mux.HandleFunc("GET /api/access-requests", auth.ListAccessRequests(cfg))
	mux.HandleFunc("POST /api/access-requests/{email}/approve", auth.ApproveAccessRequest(cfg))
	mux.HandleFunc("DELETE /api/access-requests/{email}", auth.DenyAccessRequest(cfg))

	// Serve the site at the root.
	if cfg.HasExternalSite() {
		// External build system: serve pre-built static files.
		mux.Handle("/", http.FileServer(http.Dir(cfg.SiteDir())))
		log.Printf("Using external build command for site")
	} else {
		// Built-in site: render dynamically from embedded templates.
		csvPath := filepath.Join(cfg.AuthDir, "can-post.csv")
		siteHandler, err := site.NewHandler(cfg.ContentDir, csvPath, cfg.SiteName())
		if err != nil {
			log.Fatalf("Failed to create site handler: %v", err)
		}
		siteHandler.SetRoleFunc(func(r *http.Request) string {
			return auth.RoleFromContext(r.Context())
		})
		mux.Handle("/", siteHandler)
		log.Printf("Using built-in site renderer")
	}

	// Wrap all routes with auth middleware.
	handler := auth.Middleware(cfg, mux)

	// Run an initial site build on startup (no-op if no build command).
	rebuild.Trigger(cfg)

	srv := &http.Server{
		Addr:              cfg.Listen,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      5 * time.Minute, // generous for TUS uploads
	}
	log.Printf("Listening on %s", cfg.Listen)
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
