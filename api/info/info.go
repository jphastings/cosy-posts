package info

import (
	"encoding/json"
	"io/fs"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/jphastings/cosy-posts/api/config"
)

// Version and GitSHA are set at build time via ldflags.
var (
	Version = "dev"
	GitSHA  = "unknown"
)

type Response struct {
	Name    string `json:"name"`
	Version string `json:"version"`
	GitSHA  string `json:"git_sha"`
	Stats   Stats  `json:"stats"`
}

type Stats struct {
	Posts  int `json:"posts"`
	Photos int `json:"photos"`
	Videos int `json:"videos"`
	Audio  int `json:"audio"`
}

func Handler(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		stats := countContent(cfg.ContentDir)

		resp := Response{
			Name:    cfg.SiteName(),
			Version: Version,
			GitSHA:  GitSHA,
			Stats:   stats,
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}
}

func countContent(contentDir string) Stats {
	var stats Stats

	filepath.WalkDir(contentDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}

		name := strings.ToLower(d.Name())

		// A post directory contains an index file
		if name == "index.md" || name == "index.djot" {
			stats.Posts++
			return nil
		}

		ext := strings.ToLower(filepath.Ext(name))
		switch ext {
		case ".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic":
			stats.Photos++
		case ".mp4", ".mov", ".webm":
			stats.Videos++
		case ".m4a", ".mp3", ".wav", ".aac":
			stats.Audio++
		}

		return nil
	})

	return stats
}
