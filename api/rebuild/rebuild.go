package rebuild

import (
	"log"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/jphastings/cosy-posts/api/config"
)

// Trigger runs the configured rebuild command in a background goroutine.
// stdout and stderr are appended to the configured log file.
// This function returns immediately without waiting for the command to finish.
func Trigger(cfg *config.Config) {
	if cfg.RebuildCmd() == "" {
		log.Println("No rebuild command configured, skipping")
		return
	}

	go func() {
		log.Printf("Triggering rebuild: %s", cfg.RebuildCmd())

		cmd := exec.Command("sh", "-c", cfg.RebuildCmd())
		cmd.Dir = cfg.Dir
		cmd.Env = append(os.Environ(),
			"CAN_POST_CSV="+filepath.Join(cfg.Dir, "can-post.csv"),
			"SITE_NAME="+cfg.SiteName(),
		)

		// Open log file in append mode.
		logFile, err := os.OpenFile(cfg.LogFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
		if err != nil {
			log.Printf("Error opening rebuild log file %s: %v", cfg.LogFile, err)
			return
		}
		defer logFile.Close()

		cmd.Stdout = logFile
		cmd.Stderr = logFile

		if err := cmd.Run(); err != nil {
			log.Printf("Rebuild command failed: %v", err)
			return
		}

		log.Println("Rebuild completed successfully")
	}()
}
