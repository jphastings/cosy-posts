package feed

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/xml"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jphastings/cosy-posts/api/auth"
	"github.com/jphastings/cosy-posts/api/config"
	"github.com/jphastings/cosy-posts/api/internal/content"
	"github.com/yuin/goldmark"
)

const maxItems = 50

type frontmatter struct {
	Date   string `yaml:"date"`
	Author string `yaml:"author"`
}

// rss is the top-level RSS 2.0 document.
type rss struct {
	XMLName xml.Name `xml:"rss"`
	Version string   `xml:"version,attr"`
	AtomNS  string   `xml:"xmlns:atom,attr"`
	Channel channel  `xml:"channel"`
}

type channel struct {
	Title         string   `xml:"title"`
	Link          string   `xml:"link"`
	Description   string   `xml:"description"`
	LastBuildDate string   `xml:"lastBuildDate,omitempty"`
	AtomLink      atomLink `xml:"atom:link"`
	Items         []item   `xml:"item"`
}

type atomLink struct {
	Href string `xml:"href,attr"`
	Rel  string `xml:"rel,attr"`
	Type string `xml:"type,attr"`
}

type item struct {
	Title       string    `xml:"title"`
	Link        string    `xml:"link"`
	GUID        guidElem  `xml:"guid"`
	PubDate     string    `xml:"pubDate"`
	Description cdata     `xml:"description"`
	Enclosures  []encl    `xml:"enclosure,omitempty"`
}

type guidElem struct {
	IsPermaLink bool   `xml:"isPermaLink,attr"`
	Value       string `xml:",chardata"`
}

type encl struct {
	URL    string `xml:"url,attr"`
	Type   string `xml:"type,attr"`
	Length int64  `xml:"length,attr"`
}

// cdata wraps content in CDATA for XML output.
type cdata struct {
	Content string `xml:",cdata"`
}

// Handler returns an HTTP handler that serves an RSS 2.0 feed.
// It performs Basic Auth using HMAC-SHA256(email, rssSecret) as the password.
func Handler(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if cfg.RSSSecret == "" {
			http.NotFound(w, r)
			return
		}

		email, password, ok := r.BasicAuth()
		if !ok {
			w.Header().Set("WWW-Authenticate", `Basic realm="RSS Feed"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		email = strings.ToLower(strings.TrimSpace(email))
		if !validFeedPassword(email, cfg.RSSSecret, password) || auth.LookupRole(cfg.AuthDir, email) == "" {
			w.Header().Set("WWW-Authenticate", `Basic realm="RSS Feed"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		baseURL := requestBaseURL(r)
		feedXML, err := buildFeed(cfg, baseURL)
		if err != nil {
			log.Printf("feed: build: %v", err)
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/rss+xml; charset=utf-8")
		w.Header().Set("Cache-Control", "private, max-age=3600")
		w.Write(feedXML)
	}
}

// FeedPassword computes the HMAC-SHA256 password for a given email and secret.
func FeedPassword(email, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(strings.ToLower(strings.TrimSpace(email))))
	return hex.EncodeToString(mac.Sum(nil))
}

func validFeedPassword(email, secret, password string) bool {
	expected := FeedPassword(email, secret)
	return hmac.Equal([]byte(expected), []byte(password))
}

func requestBaseURL(r *http.Request) string {
	scheme := "https"
	if proto := r.Header.Get("X-Forwarded-Proto"); proto != "" {
		scheme = proto
	} else if r.TLS == nil {
		scheme = "http"
	}
	return scheme + "://" + r.Host
}

type postEntry struct {
	date    time.Time
	author  string
	body    string
	media   []mediaRef
	postURL string
}

type mediaRef struct {
	url     string
	isVideo bool
}

func buildFeed(cfg *config.Config, baseURL string) ([]byte, error) {
	posts := loadPosts(cfg.ContentDir, baseURL)

	var items []item
	for _, p := range posts {
		desc := buildDescription(p)

		var enclosures []encl
		for _, m := range p.media {
			enclosures = append(enclosures, encl{
				URL:  m.url,
				Type: mediaMIME(m),
			})
		}

		title := p.date.Format("2 Jan 2006")
		if p.author != "" {
			title = p.author + " — " + title
		}

		items = append(items, item{
			Title:       title,
			Link:        baseURL + p.postURL,
			GUID:        guidElem{IsPermaLink: true, Value: baseURL + p.postURL},
			PubDate:     p.date.Format(time.RFC1123Z),
			Description: cdata{Content: desc},
			Enclosures:  enclosures,
		})
	}

	siteName := cfg.SiteName()
	if siteName == "" {
		siteName = "Cosy Posts"
	}

	var lastBuild string
	if len(posts) > 0 {
		lastBuild = posts[0].date.Format(time.RFC1123Z)
	}

	feed := rss{
		Version: "2.0",
		AtomNS:  "http://www.w3.org/2005/Atom",
		Channel: channel{
			Title:         siteName,
			Link:          baseURL + "/",
			Description:   siteName + " — recent posts",
			LastBuildDate: lastBuild,
			AtomLink: atomLink{
				Href: baseURL + "/feed.xml",
				Rel:  "self",
				Type: "application/rss+xml",
			},
			Items: items,
		},
	}

	var buf bytes.Buffer
	buf.WriteString(xml.Header)
	enc := xml.NewEncoder(&buf)
	enc.Indent("", "  ")
	if err := enc.Encode(feed); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func loadPosts(contentDir, baseURL string) []postEntry {
	var posts []postEntry

	filepath.Walk(contentDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		name := info.Name()
		if name != "index.md" && name != "index.djot" {
			return nil
		}

		// Skip site-level index.
		if filepath.Dir(path) == contentDir {
			return nil
		}

		raw, err := os.ReadFile(path)
		if err != nil {
			return nil
		}

		fm, body := content.ParseFrontmatter[frontmatter](raw)

		postDir := filepath.Dir(path)
		rel, _ := filepath.Rel(contentDir, postDir)
		postURL := "/content/" + filepath.ToSlash(rel) + "/"

		var postDate time.Time
		if fm.Date != "" {
			postDate, _ = time.Parse(time.RFC3339, fm.Date)
			if postDate.IsZero() {
				postDate, _ = time.Parse("2006-01-02", fm.Date)
			}
		}

		// Find media files.
		var media []mediaRef
		entries, _ := os.ReadDir(postDir)
		for _, e := range entries {
			ext := strings.ToLower(filepath.Ext(e.Name()))
			if !content.MediaExts[ext] {
				continue
			}
			media = append(media, mediaRef{
				url:     baseURL + postURL + e.Name(),
				isVideo: content.VideoExts[ext],
			})
		}
		sort.Slice(media, func(i, j int) bool {
			return media[i].url < media[j].url
		})

		posts = append(posts, postEntry{
			date:    postDate,
			author:  fm.Author,
			body:    body,
			media:   media,
			postURL: postURL,
		})
		return nil
	})

	sort.Slice(posts, func(i, j int) bool {
		return posts[i].date.After(posts[j].date)
	})

	if len(posts) > maxItems {
		posts = posts[:maxItems]
	}

	return posts
}

func buildDescription(p postEntry) string {
	var buf bytes.Buffer

	// Render body markdown to HTML.
	if p.body != "" {
		goldmark.Convert([]byte(p.body), &buf)
	}

	// Append media as HTML.
	for _, m := range p.media {
		if m.isVideo {
			fmt.Fprintf(&buf, `<p><video src="%s" controls></video></p>`, m.url)
		} else {
			fmt.Fprintf(&buf, `<p><img src="%s" /></p>`, m.url)
		}
	}

	return buf.String()
}

func mediaMIME(m mediaRef) string {
	ext := strings.ToLower(filepath.Ext(m.url))
	switch ext {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	case ".mp4":
		return "video/mp4"
	case ".mov":
		return "video/quicktime"
	case ".webm":
		return "video/webm"
	case ".m4a":
		return "audio/mp4"
	case ".mp3":
		return "audio/mpeg"
	default:
		return "application/octet-stream"
	}
}
