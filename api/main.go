package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"path/filepath"

	"github.com/jphastings/cosy-posts/api/auth"
	"github.com/jphastings/cosy-posts/api/config"
	"github.com/jphastings/cosy-posts/api/info"
	"github.com/jphastings/cosy-posts/api/notify"
	"github.com/jphastings/cosy-posts/api/rebuild"
	flag "github.com/spf13/pflag"
)

func main() {
	configPath := flag.String("config", "", "path to YAML config file")
	flag.Parse()

	log.Printf("cosy-posts %s (%s)", info.Version, info.GitSHA)

	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Validate auth CSV files exist.
	if err := auth.ValidateAuthFiles(cfg.AuthDir); err != nil {
		log.Fatalf("Auth configuration error: %v", err)
	}

	stopCleanup := auth.StartCleanup(cfg.AuthDir)
	defer stopCleanup()

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

	notifyList, err := notify.NewList(filepath.Join(cfg.AuthDir, "email-notify.txt"))
	if err != nil {
		log.Fatalf("Failed to create notify list: %v", err)
	}
	defer notifyList.Close()

	handler, err := newHandler(cfg, notifyList)
	if err != nil {
		log.Fatalf("Failed to create handler: %v", err)
	}

	// Run an initial site build on startup (no-op if no build command).
	rebuild.Trigger(cfg)

	// Start email notification scheduler.
	stopNotify := notify.StartScheduler(cfg, notifyList)
	defer stopNotify()

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
