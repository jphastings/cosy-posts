package upload

import (
	"log"
	"net/http"
	"sync"

	"github.com/jphastings/cosy-posts/api/config"

	"github.com/tus/tusd/v2/pkg/filelocker"
	"github.com/tus/tusd/v2/pkg/filestore"
	tusd "github.com/tus/tusd/v2/pkg/handler"
)

// CompletionFunc is called when a body upload completes.
// It receives the post ID, upload info, and path to the uploaded file.
type CompletionFunc func(event tusd.HookEvent)

// Handler wraps the tusd handler and manages upload tracking.
type Handler struct {
	tusHandler *tusd.Handler
	onBodyDone CompletionFunc
	mu         sync.Mutex
	cfg        *config.Config
}

// NewHandler creates a new TUS upload handler.
// onBodyDone is called when a body upload (role=body) completes.
func NewHandler(cfg *config.Config, onBodyDone CompletionFunc) (*Handler, error) {
	store := filestore.New(cfg.TUSUploadDir())
	locker := filelocker.New(cfg.TUSUploadDir())

	composer := tusd.NewStoreComposer()
	store.UseIn(composer)
	locker.UseIn(composer)

	tusHandler, err := tusd.NewHandler(tusd.Config{
		BasePath:              "/files/",
		StoreComposer:         composer,
		NotifyCompleteUploads: true,
	})
	if err != nil {
		return nil, err
	}

	h := &Handler{
		tusHandler: tusHandler,
		onBodyDone: onBodyDone,
		cfg:        cfg,
	}

	// Listen for completed uploads in background.
	go h.listenForCompleted()

	return h, nil
}

// ServeHTTP delegates to the tusd handler.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.tusHandler.ServeHTTP(w, r)
}

// listenForCompleted processes upload completion events from tusd.
func (h *Handler) listenForCompleted() {
	for {
		event := <-h.tusHandler.CompleteUploads
		info := event.Upload

		postID := info.MetaData["post-id"]
		role := info.MetaData["role"]

		if postID == "" {
			log.Printf("Upload %s completed without post-id metadata, skipping", info.ID)
			continue
		}

		log.Printf("Upload completed: id=%s post-id=%s role=%s filename=%s",
			info.ID, postID, role, info.MetaData["filename"])

		// When a body upload completes, trigger post assembly.
		if role == "body" {
			if h.onBodyDone != nil {
				h.onBodyDone(event)
			}
		}
	}
}
