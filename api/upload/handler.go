package upload

import (
	"fmt"
	"log"
	"net/http"
	"net/url"

	"github.com/jphastings/cosy-posts/api/config"

	"github.com/tus/tusd/v2/pkg/filelocker"
	"github.com/tus/tusd/v2/pkg/filestore"
	tusd "github.com/tus/tusd/v2/pkg/handler"
)

// CompletionFunc is called when a body upload completes.
// It receives the hook event and returns an error if post assembly fails.
type CompletionFunc func(event tusd.HookEvent) error

// Handler wraps the tusd handler and manages upload tracking.
type Handler struct {
	tusHandler *tusd.Handler
	onBodyDone CompletionFunc
	cfg        *config.Config
}

// NewHandler creates a new TUS upload handler.
// onBodyDone is called synchronously when a body upload completes,
// before the response is sent to the client.
func NewHandler(cfg *config.Config, onBodyDone CompletionFunc) (*Handler, error) {
	store := filestore.New(cfg.TUSUploadDir())
	locker := filelocker.New(cfg.TUSUploadDir())

	composer := tusd.NewStoreComposer()
	store.UseIn(composer)
	locker.UseIn(composer)

	h := &Handler{
		onBodyDone: onBodyDone,
		cfg:        cfg,
	}

	tusHandler, err := tusd.NewHandler(tusd.Config{
		BasePath:                  "/files/",
		StoreComposer:             composer,
		PreFinishResponseCallback: h.preFinishResponse,
	})
	if err != nil {
		return nil, err
	}

	h.tusHandler = tusHandler
	return h, nil
}

// ServeHTTP delegates to the tusd handler, rewriting any absolute Location
// header to a relative path so clients behind reverse proxies get the correct URL.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.tusHandler.ServeHTTP(&relativeLocationWriter{ResponseWriter: w}, r)
}

// preFinishResponse is called by tusd after an upload completes but before the
// response is sent. This lets us run post assembly synchronously so failures
// are reported back to the client.
func (h *Handler) preFinishResponse(event tusd.HookEvent) (tusd.HTTPResponse, error) {
	info := event.Upload
	postID := info.MetaData["post-id"]
	role := info.MetaData["role"]

	if postID == "" {
		log.Printf("Upload %s completed without post-id metadata, skipping", info.ID)
		return tusd.HTTPResponse{}, nil
	}

	log.Printf("Upload completed: id=%s post-id=%s role=%s filename=%s",
		info.ID, postID, role, info.MetaData["filename"])

	if role == "body" && h.onBodyDone != nil {
		if err := h.onBodyDone(event); err != nil {
			log.Printf("Post assembly failed for %s: %v", postID, err)
			return tusd.HTTPResponse{}, fmt.Errorf("post assembly failed: %w", err)
		}
	}

	return tusd.HTTPResponse{}, nil
}

// relativeLocationWriter wraps an http.ResponseWriter to rewrite absolute
// Location headers to relative paths. tusd generates absolute URLs using
// the inbound request's scheme/host, which is wrong behind a reverse proxy.
type relativeLocationWriter struct {
	http.ResponseWriter
}

func (w *relativeLocationWriter) WriteHeader(statusCode int) {
	if loc := w.Header().Get("Location"); loc != "" {
		if u, err := url.Parse(loc); err == nil && u.IsAbs() {
			w.Header().Set("Location", u.RequestURI())
		}
	}
	w.ResponseWriter.WriteHeader(statusCode)
}

// Unwrap returns the underlying ResponseWriter so http.NewResponseController
// can access connection-level methods (SetReadDeadline, SetWriteDeadline).
func (w *relativeLocationWriter) Unwrap() http.ResponseWriter {
	return w.ResponseWriter
}
