package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"github.com/jphastings/cosy-posts/api/auth"
	"github.com/jphastings/cosy-posts/api/config"
	"github.com/jphastings/cosy-posts/api/rebuild"
	flag "github.com/spf13/pflag"
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

	handler, err := newHandler(cfg)
	if err != nil {
		log.Fatalf("Failed to create handler: %v", err)
	}

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
