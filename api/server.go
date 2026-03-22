package main

import (
	"log"
	"net/http"
	"path/filepath"

	"github.com/jphastings/cosy-posts/api/auth"
	"github.com/jphastings/cosy-posts/api/config"
	"github.com/jphastings/cosy-posts/api/feed"
	"github.com/jphastings/cosy-posts/api/info"
	"github.com/jphastings/cosy-posts/api/notify"
	"github.com/jphastings/cosy-posts/api/post"
	"github.com/jphastings/cosy-posts/api/rebuild"
	"github.com/jphastings/cosy-posts/api/site"
	"github.com/jphastings/cosy-posts/api/upload"

	tusd "github.com/tus/tusd/v2/pkg/handler"
)

// newHandler builds the complete HTTP handler with all routes and middleware.
// This is the single source of truth for the server's routing — used by both
// main() and the contract tests.
func newHandler(cfg *config.Config, notifyList *notify.List) (http.Handler, error) {
	onBodyDone := func(event tusd.HookEvent) error {
		postID := event.Upload.MetaData["post-id"]
		log.Printf("Body upload completed for post %s, starting assembly", postID)

		if err := post.Assemble(cfg, event); err != nil {
			return err
		}

		rebuild.Trigger(cfg)
		return nil
	}

	uploadHandler, err := upload.NewHandler(cfg, onBodyDone)
	if err != nil {
		return nil, err
	}

	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	mux.HandleFunc("GET /api/info", info.Handler(cfg))
	mux.HandleFunc("GET /api/info/site", info.SiteInfoHandler(cfg))
	mux.HandleFunc("GET /feed.xml", feed.Handler(cfg))

	mux.Handle("/files/", http.StripPrefix("/files/", uploadHandler))
	mux.Handle("/files", http.StripPrefix("/files", uploadHandler))

	mux.HandleFunc("GET /auth/login", auth.LoginPage(cfg))
	mux.HandleFunc("POST /auth/send", auth.SendLink(cfg))
	mux.HandleFunc("GET /auth/verify", auth.Verify(cfg))

	mux.HandleFunc("DELETE /api/posts/{id}", post.DeleteHandler(cfg))

	mux.HandleFunc("POST /api/email-notify", notify.Handler(notifyList))

	mux.HandleFunc("GET /api/access-requests", auth.ListAccessRequests(cfg))
	mux.HandleFunc("POST /api/access-requests/{email}/approve", auth.ApproveAccessRequest(cfg))
	mux.HandleFunc("DELETE /api/access-requests/{email}", auth.DenyAccessRequest(cfg))

	if cfg.HasExternalSite() {
		mux.Handle("/", http.FileServer(http.Dir(cfg.SiteDir())))
		log.Printf("Using external build command for site")
	} else {
		csvPath := filepath.Join(cfg.AuthDir, "can-post.csv")
		siteHandler, err := site.NewHandler(cfg.ContentDir, csvPath, cfg.SiteName())
		if err != nil {
			return nil, err
		}
		siteHandler.SetRoleFunc(func(r *http.Request) string {
			return auth.RoleFromContext(r.Context())
		})
		siteHandler.SetEmailNotifyFunc(func(r *http.Request) bool {
			return notifyList.Has(auth.EmailFromContext(r.Context()))
		})
		siteHandler.SetFeedURLFunc(func(r *http.Request) string {
			if cfg.RSSSecret == "" {
				return ""
			}
			email := auth.EmailFromContext(r.Context())
			if email == "" {
				return ""
			}
			scheme := "https"
			if proto := r.Header.Get("X-Forwarded-Proto"); proto != "" {
				scheme = proto
			} else if r.TLS == nil {
				scheme = "http"
			}
			return feed.SignURL(scheme+"://"+r.Host+"/feed.xml", email, cfg.RSSSecret)
		})
		mux.Handle("/", siteHandler)
		log.Printf("Using built-in site renderer")
	}

	return auth.Middleware(cfg, mux), nil
}
