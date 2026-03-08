package info

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/jphastings/cosy-posts/api/config"
	"github.com/yuin/goldmark"
	"gopkg.in/yaml.v3"
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
		prefLang := preferredLang(r)
		html := loadSiteInfo(cfg.ContentDir, prefLang)

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"html": string(html),
		})
	}
}

func preferredLang(r *http.Request) string {
	accept := r.Header.Get("Accept-Language")
	if accept == "" {
		return ""
	}
	for _, part := range strings.Split(accept, ",") {
		tag := strings.TrimSpace(strings.SplitN(part, ";", 2)[0])
		if tag == "" || tag == "*" {
			continue
		}
		lang, _, _ := strings.Cut(tag, "-")
		return strings.ToLower(lang)
	}
	return ""
}

func loadSiteInfo(contentDir, prefLang string) string {
	if prefLang != "" {
		for _, ext := range []string{".md", ".djot"} {
			path := filepath.Join(contentDir, "index."+prefLang+ext)
			raw, err := os.ReadFile(path)
			if err == nil {
				body := extractBody(raw)
				if body != "" {
					var buf bytes.Buffer
					goldmark.Convert([]byte(body), &buf)
					return buf.String()
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
		body := extractBody(raw)
		if body != "" {
			var buf bytes.Buffer
			goldmark.Convert([]byte(body), &buf)
			return buf.String()
		}
	}
	return ""
}

func extractBody(raw []byte) string {
	content := string(raw)
	if !strings.HasPrefix(content, "---\n") {
		return strings.TrimSpace(content)
	}
	end := strings.Index(content[4:], "\n---\n")
	if end == -1 {
		return strings.TrimSpace(content)
	}
	return strings.TrimSpace(content[4+end+5:])
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
		if locale, ok := parseTranslationFilename(name); ok {
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
	content := string(raw)
	if !strings.HasPrefix(content, "---\n") {
		return ""
	}
	end := strings.Index(content[4:], "\n---\n")
	if end == -1 {
		return ""
	}
	var fm struct {
		Locale string `yaml:"locale"`
	}
	yaml.Unmarshal([]byte(content[4:4+end]), &fm)
	return fm.Locale
}

func parseTranslationFilename(name string) (string, bool) {
	for _, ext := range []string{".md", ".djot"} {
		prefix := "index."
		if strings.HasPrefix(name, prefix) && strings.HasSuffix(name, ext) {
			lang := strings.TrimPrefix(name, prefix)
			lang = strings.TrimSuffix(lang, ext)
			if lang != "" && !strings.Contains(lang, ".") {
				return lang, true
			}
		}
	}
	return "", false
}
