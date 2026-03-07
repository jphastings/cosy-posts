package post

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/jphastings/cosy-posts/api/auth"
	"github.com/jphastings/cosy-posts/api/config"
	"github.com/jphastings/cosy-posts/api/rebuild"
)

// DeleteHandler returns an HTTP handler for DELETE /api/posts/{id}.
// Only users with the "post" role may delete posts.
func DeleteHandler(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		role := auth.RoleFromContext(r.Context())
		if role != "post" {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}

		postID := r.PathValue("id")
		if postID == "" || strings.Contains(postID, "/") || strings.Contains(postID, "..") {
			http.Error(w, `{"error":"invalid post id"}`, http.StatusBadRequest)
			return
		}

		// Find the post directory by searching content_dir for a matching nanoid.
		postDir, err := findPostDir(cfg.ContentDir, postID)
		if err != nil {
			http.Error(w, `{"error":"post not found"}`, http.StatusNotFound)
			return
		}

		if err := os.RemoveAll(postDir); err != nil {
			log.Printf("delete post %s: %v", postID, err)
			http.Error(w, `{"error":"failed to delete post"}`, http.StatusInternalServerError)
			return
		}

		log.Printf("Post deleted: %s (%s)", postID, postDir)

		// Trigger site rebuild.
		rebuild.Trigger(cfg)

		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"ok":true}`)
	}
}

// findPostDir walks the content directory to find a post directory matching
// the given nanoid. Returns the full path or an error if not found.
func findPostDir(contentDir, postID string) (string, error) {
	var found string
	err := filepath.Walk(contentDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() && info.Name() == postID {
			// Verify it contains an index file.
			for _, name := range []string{"index.md", "index.djot"} {
				if _, err := os.Stat(filepath.Join(path, name)); err == nil {
					found = path
					return filepath.SkipAll
				}
			}
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	if found == "" {
		return "", fmt.Errorf("post %s not found", postID)
	}
	return found, nil
}
