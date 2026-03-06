package rebuild

import (
	"log"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/jphastings/cosy-posts/api/config"
)

// Trigger runs the configured rebuild command in a background goroutine.
// stdout and stderr are sent to the process's own stdout/stderr.
// This function returns immediately without waiting for the command to finish.
func Trigger(cfg *config.Config) {
	if !cfg.HasExternalSite() {
		log.Println("No external site configured, skipping rebuild")
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
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		if err := cmd.Run(); err != nil {
			log.Printf("Rebuild command failed: %v", err)
			return
		}

		log.Println("Rebuild completed successfully")
	}()
}
