package notify

import (
	"bufio"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"

	"github.com/jphastings/cosy-posts/api/auth"
)

// List manages an in-memory set of email addresses that have opted into
// email notifications, backed by a text file (one address per line).
// Writes are queued so concurrent updates don't race on the file.
type List struct {
	mu      sync.Mutex
	emails  map[string]bool
	path    string
	writeCh chan struct{}
	done    chan struct{}
}

// NewList loads the notification list from path (creating the file if
// missing) and starts a background goroutine for queued writes.
func NewList(path string) (*List, error) {
	l := &List{
		emails:  make(map[string]bool),
		path:    path,
		writeCh: make(chan struct{}, 1),
		done:    make(chan struct{}),
	}

	if err := l.load(); err != nil {
		return nil, err
	}

	go l.writeLoop()
	return l, nil
}

// Close stops the background writer. Call on shutdown.
func (l *List) Close() {
	close(l.writeCh)
	<-l.done
}

// Has returns whether the given email has notifications enabled.
func (l *List) Has(email string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.emails[strings.ToLower(strings.TrimSpace(email))]
}

// Set enables or disables notifications for the given email.
func (l *List) Set(email string, enabled bool) {
	email = strings.ToLower(strings.TrimSpace(email))
	l.mu.Lock()
	changed := l.emails[email] != enabled
	if enabled {
		l.emails[email] = true
	} else {
		delete(l.emails, email)
	}
	l.mu.Unlock()

	if changed {
		l.queueWrite()
	}
}

func (l *List) load() error {
	f, err := os.Open(l.path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line != "" {
			l.emails[strings.ToLower(line)] = true
		}
	}
	return scanner.Err()
}

func (l *List) queueWrite() {
	select {
	case l.writeCh <- struct{}{}:
	default:
		// Write already queued.
	}
}

func (l *List) writeLoop() {
	defer close(l.done)
	for range l.writeCh {
		l.mu.Lock()
		lines := make([]string, 0, len(l.emails))
		for email := range l.emails {
			lines = append(lines, email)
		}
		l.mu.Unlock()

		data := []byte(strings.Join(lines, "\n") + "\n")
		if len(lines) == 0 {
			data = nil
		}
		if err := os.WriteFile(l.path, data, 0o644); err != nil {
			log.Printf("notify: write %s: %v", l.path, err)
		}
	}
}

// Handler returns an HTTP handler for POST /api/email-notify.
// It toggles the authenticated user's notification preference.
func Handler(list *List) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		email := auth.EmailFromContext(r.Context())
		if email == "" {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}

		if err := r.ParseForm(); err != nil {
			http.Error(w, `{"error":"bad request"}`, http.StatusBadRequest)
			return
		}

		enabled := r.FormValue("enabled") != ""
		list.Set(email, enabled)

		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"enabled":%t}`, enabled)
	}
}
