package content

import (
	"bytes"
	"strings"

	"github.com/yuin/goldmark"
	"gopkg.in/yaml.v3"
)

// VideoExts lists extensions for video files.
var VideoExts = map[string]bool{
	".mp4": true, ".mov": true, ".webm": true,
}

// ImageExts lists extensions for image files whose dimensions we can decode.
var ImageExts = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true,
}

// MediaExts lists all recognised media extensions.
var MediaExts = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true,
	".mp4": true, ".mov": true, ".webm": true,
	".m4a": true, ".mp3": true,
}

// ParseTranslationFilename checks if a filename matches index.{lang}.md or
// index.{lang}.djot and returns the language code.
func ParseTranslationFilename(name string) (string, bool) {
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

// PreferredLang extracts the first language code from the Accept-Language header value.
func PreferredLang(accept string) string {
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

// ParseFrontmatter splits raw file content into frontmatter and body text.
func ParseFrontmatter[T any](raw []byte) (T, string) {
	content := string(raw)
	var fm T

	if !strings.HasPrefix(content, "---\n") {
		return fm, strings.TrimSpace(content)
	}

	end := strings.Index(content[4:], "\n---\n")
	if end == -1 {
		return fm, strings.TrimSpace(content)
	}

	fmStr := content[4 : 4+end]
	body := content[4+end+5:]

	yaml.Unmarshal([]byte(fmStr), &fm)
	return fm, strings.TrimSpace(body)
}

// ExtractBody strips frontmatter and returns only the body text.
func ExtractBody(raw []byte) string {
	type empty struct{}
	_, body := ParseFrontmatter[empty](raw)
	return body
}

// RenderMarkdown converts markdown body text to HTML.
func RenderMarkdown(body string) string {
	var buf bytes.Buffer
	goldmark.Convert([]byte(body), &buf)
	return buf.String()
}
