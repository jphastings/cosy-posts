package info

import (
	"bufio"
	"encoding/json"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/jphastings/cosy-posts/api/config"
	"github.com/jphastings/cosy-posts/api/internal/content"
)

// Version and GitSHA are set at build time via ldflags.
var (
	Version = "dev"
	GitSHA  = "unknown"
)

type Response struct {
	Name    string   `json:"name"`
	Version string   `json:"version"`
	GitSHA  string   `json:"git_sha"`
	Stats   Stats    `json:"stats"`
	Locales []string `json:"locales"`
}

type Stats struct {
	Posts   int `json:"posts"`
	Photos  int `json:"photos"`
	Videos  int `json:"videos"`
	Audio   int `json:"audio"`
	Members int `json:"members"`
}

func Handler(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		stats, locales := countContent(cfg.ContentDir)
		stats.Members = countMembers(cfg.AuthDir)

		resp := Response{
			Name:    cfg.SiteName(),
			Version: Version,
			GitSHA:  GitSHA,
			Stats:   stats,
			Locales: locales,
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}
}

// SiteInfoHandler returns the rendered site-level index.md content as JSON.
// Supports Accept-Language header for locale fallback.
func SiteInfoHandler(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		prefLang := content.PreferredLang(r.Header.Get("Accept-Language"))
		html := loadSiteInfo(cfg.ContentDir, prefLang)

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"html": string(html),
		})
	}
}

func loadSiteInfo(contentDir, prefLang string) string {
	if prefLang != "" {
		for _, ext := range []string{".md", ".djot"} {
			path := filepath.Join(contentDir, "index."+prefLang+ext)
			raw, err := os.ReadFile(path)
			if err == nil {
				body := content.ExtractBody(raw)
				if body != "" {
					return content.RenderMarkdown(body)
				}
			}
		}
	}
	for _, name := range []string{"index.md", "index.djot"} {
		path := filepath.Join(contentDir, name)
		raw, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		body := content.ExtractBody(raw)
		if body != "" {
			return content.RenderMarkdown(body)
		}
	}
	return ""
}

func countContent(contentDir string) (Stats, []string) {
	var stats Stats
	localeSet := make(map[string]bool)

	absContentDir, _ := filepath.Abs(contentDir)

	filepath.WalkDir(contentDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}

		name := d.Name()
		nameLower := strings.ToLower(name)

		// A post directory contains an index file
		if nameLower == "index.md" || nameLower == "index.djot" {
			// Skip site-level index in the content root.
			absPath, _ := filepath.Abs(filepath.Dir(path))
			if absPath == absContentDir {
				return nil
			}
			stats.Posts++
			// Extract locale from frontmatter.
			if raw, err := os.ReadFile(path); err == nil {
				locale := extractLocaleFromFrontmatter(raw)
				if locale != "" {
					localeSet[locale] = true
				}
			}
			return nil
		}

		// Check for translation files like index.es.md
		if locale, ok := content.ParseTranslationFilename(name); ok {
			localeSet[locale] = true
			return nil
		}

		ext := strings.ToLower(filepath.Ext(nameLower))
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

	// Sort locales for stable output.
	locales := make([]string, 0, len(localeSet))
	for l := range localeSet {
		locales = append(locales, l)
	}
	sort.Strings(locales)

	return stats, locales
}

func countMembers(authDir string) int {
	count := 0
	for _, name := range []string{"can-post.csv", "can-view.csv"} {
		f, err := os.Open(filepath.Join(authDir, name))
		if err != nil {
			continue
		}
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			if strings.TrimSpace(scanner.Text()) != "" {
				count++
			}
		}
		f.Close()
	}
	return count
}

func extractLocaleFromFrontmatter(raw []byte) string {
	type localeFM struct {
		Locale string `yaml:"locale"`
	}
	fm, _ := content.ParseFrontmatter[localeFM](raw)
	return fm.Locale
}
