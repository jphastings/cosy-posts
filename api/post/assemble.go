package post

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"log"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
	"unicode"

	"github.com/jphastings/cosy-posts/api/config"
	"github.com/jphastings/cosy-posts/api/internal/content"
	"github.com/jphastings/cosy-posts/api/photo"
	"github.com/jphastings/cosy-posts/api/video"

	goexif "github.com/rwcarlsen/goexif/exif"
	tusd "github.com/tus/tusd/v2/pkg/handler"
	_ "golang.org/x/image/webp"
	"gopkg.in/yaml.v3"
)

// Frontmatter holds the YAML frontmatter for a post's index file.
type Frontmatter struct {
	Date             string    `yaml:"date"`
	Location         *Location `yaml:"location,omitempty"`
	Author           string    `yaml:"author,omitempty"`
	Locale           string    `yaml:"locale,omitempty"`
	Tags             []string  `yaml:"tags,omitempty"`
	MediaAspectRatio float64   `yaml:"media_aspect_ratio,omitempty"`
}

// Location holds GPS coordinates extracted from EXIF data.
type Location struct {
	Lat float64 `yaml:"lat"`
	Lng float64 `yaml:"lng"`
}

var hashtagRe = regexp.MustCompile(`#(\w+)`)

// Assemble processes a completed body upload event and assembles the post.
// It creates the post directory, processes media files, extracts metadata,
// writes the index file with frontmatter, and cleans up upload files.
// It returns an error if assembly fails.
func Assemble(cfg *config.Config, event tusd.HookEvent) error {
	info := event.Upload
	postID := info.MetaData["post-id"]
	dateStr := info.MetaData["date"]
	contentExt := info.MetaData["content-ext"]

	if postID == "" {
		return fmt.Errorf("body upload missing post-id metadata")
	}
	if dateStr == "" {
		return fmt.Errorf("body upload missing date metadata")
	}
	if contentExt == "" {
		contentExt = "md"
	}
	if contentExt != "md" && contentExt != "djot" {
		return fmt.Errorf("invalid content-ext %q: must be md or djot", contentExt)
	}

	// Parse the date to determine directory structure.
	postDate, err := time.Parse(time.RFC3339, dateStr)
	if err != nil {
		// Try date-only format.
		postDate, err = time.Parse("2006-01-02", dateStr)
		if err != nil {
			return fmt.Errorf("parsing date %q: %w", dateStr, err)
		}
	}

	// Create post directory: {content_dir}/YYYY/MM/DD/{nanoid}/
	postDir := filepath.Join(
		cfg.ContentDir,
		postDate.Format("2006"),
		postDate.Format("01"),
		postDate.Format("02"),
		postID,
	)
	if err := os.MkdirAll(postDir, 0o755); err != nil {
		return fmt.Errorf("creating post directory: %w", err)
	}

	// Read the body text from the body upload file.
	bodyPath := uploadDataPath(cfg, info.ID)
	bodyText, err := os.ReadFile(bodyPath)
	if err != nil {
		return fmt.Errorf("reading body upload: %w", err)
	}

	// Find all uploads for this post-id.
	uploads, err := findUploadsForPost(cfg, postID)
	if err != nil {
		return fmt.Errorf("finding uploads for post %s: %w", postID, err)
	}

	// Process media uploads.
	var location *Location
	for _, u := range uploads {
		// Skip the body upload itself.
		if u.MetaData["role"] == "body" {
			continue
		}

		filename := filepath.Base(u.MetaData["filename"])
		if filename == "" || filename == "." || filename == "/" {
			log.Printf("Upload %s has no filename, skipping", u.ID)
			continue
		}

		srcPath := uploadDataPath(cfg, u.ID)

		if photo.IsImage(filename) {
			// Copy to post dir with original extension for decoding.
			tmpPath := filepath.Join(postDir, filename)
			if err := copyFile(srcPath, tmpPath); err != nil {
				return fmt.Errorf("copying image %s: %w", filename, err)
			}

			// Try to extract EXIF GPS before processing (which re-encodes).
			if location == nil {
				loc := extractGPS(tmpPath)
				if loc != nil {
					location = loc
				}
			}

			// Process the image (resize + jpegli encode).
			outPath, err := photo.Process(tmpPath)
			if err != nil {
				log.Printf("Warning: failed to process image %s: %v", filename, err)
				// Keep the original file as-is.
				continue
			}

			// If the output file is different from the input, remove the input.
			if outPath != tmpPath {
				os.Remove(tmpPath)
			}
		} else {
			// Non-image media: just copy to post directory.
			dstPath := filepath.Join(postDir, filename)
			if err := copyFile(srcPath, dstPath); err != nil {
				return fmt.Errorf("copying media %s: %w", filename, err)
			}

			// Probe video files for GPS location.
			if location == nil {
				if vi, err := video.Probe(dstPath); err == nil && vi != nil && vi.Lat != nil && vi.Lng != nil {
					location = &Location{Lat: *vi.Lat, Lng: *vi.Lng}
				}
			}
		}
	}

	// Compute media aspect ratio from all images in the post directory.
	mediaAspectRatio := computeMediaAspectRatio(postDir)

	// Extract hashtags from body text.
	tags := extractTags(string(bodyText))

	// Build frontmatter.
	locale := info.MetaData["locale"]
	fm := Frontmatter{
		Date:             dateStr,
		Location:         location,
		Author:           info.MetaData["author"],
		Locale:           locale,
		Tags:             tags,
		MediaAspectRatio: mediaAspectRatio,
	}

	// Write index file.
	indexFilename := "index." + contentExt
	indexPath := filepath.Join(postDir, indexFilename)
	if err := writeIndexFile(indexPath, fm, bodyText); err != nil {
		return fmt.Errorf("writing index file: %w", err)
	}

	// Write additional locale body files (role=body-locale).
	for _, u := range uploads {
		if u.MetaData["role"] != "body-locale" {
			continue
		}
		uLocale := u.MetaData["locale"]
		uExt := u.MetaData["content-ext"]
		if uLocale == "" {
			continue
		}
		if !isValidLocale(uLocale) {
			log.Printf("Warning: invalid locale %q in upload %s, skipping", uLocale, u.ID)
			continue
		}
		if uExt == "" {
			uExt = "md"
		}
		if uExt != "md" && uExt != "djot" {
			log.Printf("Warning: invalid content-ext %q in upload %s, skipping", uExt, u.ID)
			continue
		}
		localeBodyPath := uploadDataPath(cfg, u.ID)
		localeBody, err := os.ReadFile(localeBodyPath)
		if err != nil {
			log.Printf("Warning: could not read locale body %s: %v", u.ID, err)
			continue
		}
		localeFilename := fmt.Sprintf("index.%s.%s", uLocale, uExt)
		localePath := filepath.Join(postDir, localeFilename)
		if err := os.WriteFile(localePath, localeBody, 0o644); err != nil {
			log.Printf("Warning: could not write locale file %s: %v", localeFilename, err)
		}
	}

	// Clean up tus upload files for this post.
	cleanupUploads(cfg, uploads, info.ID)

	log.Printf("Post assembled: %s -> %s", postID, postDir)
	return nil
}

// tusInfoFile represents the JSON structure of a .info file stored by tusd.
type tusInfoFile struct {
	ID       string            `json:"ID"`
	Size     int64             `json:"Size"`
	Offset   int64             `json:"Offset"`
	MetaData map[string]string `json:"MetaData"`
	Storage  map[string]string `json:"Storage"`
}

// findUploadsForPost scans the TUS upload directory for all uploads
// with the given post-id in their metadata.
func findUploadsForPost(cfg *config.Config, postID string) ([]tusInfoFile, error) {
	pattern := filepath.Join(cfg.TUSUploadDir(), "*.info")
	infoFiles, err := filepath.Glob(pattern)
	if err != nil {
		return nil, err
	}

	var matches []tusInfoFile
	for _, infoPath := range infoFiles {
		data, err := os.ReadFile(infoPath)
		if err != nil {
			log.Printf("Warning: could not read %s: %v", infoPath, err)
			continue
		}

		var info tusInfoFile
		if err := json.Unmarshal(data, &info); err != nil {
			log.Printf("Warning: could not parse %s: %v", infoPath, err)
			continue
		}

		if info.MetaData["post-id"] == postID {
			matches = append(matches, info)
		}
	}

	return matches, nil
}

// uploadDataPath returns the path to the raw upload data file for a given
// tusd upload ID.
func uploadDataPath(cfg *config.Config, uploadID string) string {
	return filepath.Join(cfg.TUSUploadDir(), uploadID)
}

// extractGPS attempts to read EXIF GPS coordinates from an image file.
func extractGPS(path string) *Location {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()

	x, err := goexif.Decode(f)
	if err != nil {
		return nil
	}

	lat, lng, err := x.LatLong()
	if err != nil {
		return nil
	}

	return &Location{Lat: lat, Lng: lng}
}

// extractTags finds all #hashtags in the body text.
func extractTags(body string) []string {
	matches := hashtagRe.FindAllStringSubmatch(body, -1)
	if len(matches) == 0 {
		return nil
	}

	seen := make(map[string]bool)
	var tags []string
	for _, m := range matches {
		tag := strings.ToLower(m[1])
		if !seen[tag] {
			seen[tag] = true
			tags = append(tags, tag)
		}
	}
	return tags
}

// writeIndexFile writes the frontmatter + body text to the index file.
func writeIndexFile(path string, fm Frontmatter, body []byte) error {
	var buf bytes.Buffer

	buf.WriteString("---\n")
	fmBytes, err := yaml.Marshal(fm)
	if err != nil {
		return fmt.Errorf("marshaling frontmatter: %w", err)
	}
	buf.Write(fmBytes)
	buf.WriteString("---\n")

	// Ensure a blank line between frontmatter and body.
	bodyStr := strings.TrimSpace(string(body))
	if bodyStr != "" {
		buf.WriteString("\n")
		buf.WriteString(bodyStr)
		buf.WriteString("\n")
	}

	return os.WriteFile(path, buf.Bytes(), 0o644)
}

// cleanupUploads removes the tus data and .info files for all uploads
// associated with a post, plus the body upload itself.
func cleanupUploads(cfg *config.Config, uploads []tusInfoFile, bodyUploadID string) {
	// Collect all upload IDs.
	ids := make(map[string]bool)
	for _, u := range uploads {
		ids[u.ID] = true
	}
	ids[bodyUploadID] = true

	for id := range ids {
		dataPath := filepath.Join(cfg.TUSUploadDir(), id)
		infoPath := dataPath + ".info"
		lockPath := dataPath + ".lock"

		os.Remove(dataPath)
		os.Remove(infoPath)
		os.Remove(lockPath)
	}
}

// computeMediaAspectRatio scans a post directory for media files, computes the
// average aspect ratio of all media with known dimensions, and clamps it
// between 4:5 (portrait) and 1.91:1 (landscape). Returns 0 if no dimensions
// could be determined.
func computeMediaAspectRatio(postDir string) float64 {
	entries, err := os.ReadDir(postDir)
	if err != nil {
		return 0
	}

	var sum float64
	var count int
	for _, e := range entries {
		ext := strings.ToLower(filepath.Ext(e.Name()))
		path := filepath.Join(postDir, e.Name())

		var w, h int
		if content.ImageExts[ext] {
			f, err := os.Open(path)
			if err != nil {
				continue
			}
			cfg, _, err := image.DecodeConfig(f)
			f.Close()
			if err != nil {
				continue
			}
			w, h = cfg.Width, cfg.Height
		} else if content.VideoExts[ext] {
			vi, err := video.Probe(path)
			if err != nil || vi == nil {
				continue
			}
			w, h = vi.Width, vi.Height
		} else {
			continue
		}

		if w > 0 && h > 0 {
			sum += float64(w) / float64(h)
			count++
		}
	}

	if count == 0 {
		return 0
	}
	avg := sum / float64(count)
	// Clamp: no more portrait than 4:5, no more landscape than 1.91:1
	return math.Max(4.0/5.0, math.Min(1.91, avg))
}

// isValidLocale checks that a locale string is a short lowercase alpha tag.
func isValidLocale(s string) bool {
	if len(s) < 2 || len(s) > 8 {
		return false
	}
	for _, r := range s {
		if !unicode.IsLetter(r) {
			return false
		}
	}
	return true
}

// copyFile copies a file from src to dst.
func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}

	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}
