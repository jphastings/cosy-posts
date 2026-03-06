package main

import (
	"flag"
	"log"
	"net/http"
	"os"
	"path/filepath"

	"chaos.awaits.us/api/auth"
	"chaos.awaits.us/api/config"
	"chaos.awaits.us/api/post"
	"chaos.awaits.us/api/rebuild"
	"chaos.awaits.us/api/site"
	"chaos.awaits.us/api/upload"

	tusd "github.com/tus/tusd/v2/pkg/handler"
)

func main() {
	configPath := flag.String("config", "config.yaml", "path to YAML config file")
	flag.Parse()

	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Ensure required directories exist.
	for _, dir := range []string{cfg.ContentDir(), cfg.TUSUploadDir(), cfg.AuthDir(), cfg.SiteDir()} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			log.Fatalf("Failed to create directory %s: %v", dir, err)
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

	// Mount TUS upload handler at /files/.
	mux.Handle("/files/", http.StripPrefix("/files/", uploadHandler))
	mux.Handle("/files", http.StripPrefix("/files", uploadHandler))

	// Auth routes.
	mux.HandleFunc("GET /auth/login", auth.LoginPage())
	mux.HandleFunc("POST /auth/send", auth.SendLink(cfg))
	mux.HandleFunc("GET /auth/verify", auth.Verify(cfg))

	// Serve the site at the root.
	if cfg.RebuildCmd() != "" {
		// External build system: serve pre-built static files.
		mux.Handle("/", http.FileServer(http.Dir(cfg.SiteDir())))
		log.Printf("Using external build command for site")
	} else {
		// Built-in site: render dynamically from embedded templates.
		csvPath := filepath.Join(cfg.Dir, "can-post.csv")
		siteHandler, err := site.NewHandler(cfg.ContentDir(), csvPath, cfg.SiteName())
		if err != nil {
			log.Fatalf("Failed to create site handler: %v", err)
		}
		mux.Handle("/", siteHandler)
		log.Printf("Using built-in site renderer")
	}

	// Wrap all routes with auth middleware.
	handler := auth.Middleware(cfg, mux)

	// Run an initial site build on startup (no-op if no build command).
	rebuild.Trigger(cfg)

	log.Printf("Listening on %s", cfg.Listen)
	if err := http.ListenAndServe(cfg.Listen, handler); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
