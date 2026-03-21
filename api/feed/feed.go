package feed

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"log"
	"net/http"
	"net/url"
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
	Locale string `yaml:"locale"`
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
	Title       string   `xml:"title"`
	Link        string   `xml:"link"`
	GUID        guidElem `xml:"guid"`
	PubDate     string   `xml:"pubDate"`
	Description cdata    `xml:"description"`
	Enclosures  []encl   `xml:"enclosure,omitempty"`
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

// SignURL appends email and sig query parameters to a URL.
func SignURL(rawURL, email, secret string) string {
	u, err := url.Parse(rawURL)
	if err != nil {
		return rawURL
	}
	q := u.Query()
	q.Set("email", email)
	q.Set("sig", auth.FeedPassword(email, secret))
	u.RawQuery = q.Encode()
	return u.String()
}

// Handler returns an HTTP handler that serves an RSS 2.0 feed.
// Authentication is handled by the auth middleware via signed URL params.
func Handler(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if cfg.RSSSecret == "" {
			http.NotFound(w, r)
			return
		}

		email := auth.EmailFromContext(r.Context())
		prefLang := content.PreferredLang(r.Header.Get("Accept-Language"))

		baseURL := requestBaseURL(r)
		feedXML, err := buildFeed(cfg, baseURL, email, prefLang)
		if err != nil {
			log.Printf("feed: build: %v", err)
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/rss+xml; charset=utf-8")
		w.Header().Set("Cache-Control", "private, max-age=3600")
		w.Header().Set("Vary", "Accept-Language")
		w.Write(feedXML)
	}
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

func buildFeed(cfg *config.Config, baseURL, email, prefLang string) ([]byte, error) {
	posts := loadPosts(cfg.ContentDir, baseURL, prefLang)

	var items []item
	for _, p := range posts {
		desc := buildDescription(p, email, cfg.RSSSecret)

		var enclosures []encl
		for _, m := range p.media {
			enclosures = append(enclosures, encl{
				URL:  SignURL(m.url, email, cfg.RSSSecret),
				Type: mediaMIME(m),
			})
		}

		title := p.date.Format("2 Jan 2006")

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
			Description:   siteName,
			LastBuildDate: lastBuild,
			AtomLink: atomLink{
				Href: SignURL(baseURL+"/feed.xml", email, cfg.RSSSecret),
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

func loadPosts(contentDir, baseURL, prefLang string) []postEntry {
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

		// Find media files (unsigned — signed at render time per user).
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

		// If there's a preferred language and it differs from the post's locale,
		// look for a matching translation file and swap in its body.
		locale := fm.Locale
		if locale == "" {
			locale = "en"
		}
		if prefLang != "" && prefLang != locale {
			for _, ext := range []string{".md", ".djot"} {
				tp := filepath.Join(postDir, "index."+prefLang+ext)
				raw, err := os.ReadFile(tp)
				if err != nil {
					continue
				}
				_, tbody := content.ParseFrontmatter[frontmatter](raw)
				if tbody != "" {
					body = tbody
				}
				break
			}
		}

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

func buildDescription(p postEntry, email, secret string) string {
	var buf bytes.Buffer

	// Render body markdown to HTML.
	if p.body != "" {
		goldmark.Convert([]byte(p.body), &buf)
	}

	// Append media as HTML with signed URLs.
	for _, m := range p.media {
		signed := SignURL(m.url, email, secret)
		if m.isVideo {
			fmt.Fprintf(&buf, `<p><video src="%s" controls></video></p>`, signed)
		} else {
			fmt.Fprintf(&buf, `<p><img src="%s" /></p>`, signed)
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
