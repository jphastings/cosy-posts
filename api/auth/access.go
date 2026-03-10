package auth

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/jphastings/cosy-posts/api/config"
)

// csvMu serializes all CSV mutations to prevent race conditions.
var csvMu sync.Mutex

// validEmail performs basic sanity checking on an email address:
// must contain exactly one @, non-empty local and domain, no whitespace or newlines.
func validEmail(email string) bool {
	if strings.ContainsAny(email, " \t\n\r") {
		return false
	}
	local, domain, ok := strings.Cut(email, "@")
	if !ok || local == "" || domain == "" {
		return false
	}
	// Must not contain a second @.
	if strings.Contains(domain, "@") {
		return false
	}
	return true
}

// readCSVEmails returns all unique emails from a CSV file, preserving order.
func readCSVEmails(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	defer f.Close()

	seen := make(map[string]bool)
	var emails []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		field, _, _ := strings.Cut(line, ",")
		email := strings.TrimSpace(strings.ToLower(field))
		if email != "" && !seen[email] {
			seen[email] = true
			emails = append(emails, email)
		}
	}
	return emails, scanner.Err()
}

// removeFromCSV removes all lines matching the given email (case-insensitive)
// and rewrites the file. Returns true if at least one line was removed.
// Caller must hold csvMu.
func removeFromCSV(path, email string) (bool, error) {
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}
	defer f.Close()

	var kept []string
	removed := false
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		field, _, _ := strings.Cut(strings.TrimSpace(line), ",")
		if strings.EqualFold(strings.TrimSpace(field), email) {
			removed = true
			continue
		}
		kept = append(kept, line)
	}
	if err := scanner.Err(); err != nil {
		return false, err
	}
	if !removed {
		return false, nil
	}

	content := ""
	if len(kept) > 0 {
		content = strings.Join(kept, "\n") + "\n"
	}
	return true, os.WriteFile(path, []byte(content), 0o644)
}

// ListAccessRequests returns the deduplicated list of emails from wants-account.csv.
// Requires "post" role.
func ListAccessRequests(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if RoleFromContext(r.Context()) != "post" {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}

		path := filepath.Join(cfg.AuthDir, "wants-account.csv")
		emails, err := readCSVEmails(path)
		if err != nil {
			log.Printf("access: list: %v", err)
			http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
			return
		}
		if emails == nil {
			emails = []string{}
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(emails)
	}
}

// ApproveAccessRequest moves an email from wants-account.csv to can-view.csv.
// Requires "post" role.
func ApproveAccessRequest(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if RoleFromContext(r.Context()) != "post" {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}

		email := strings.ToLower(r.PathValue("email"))
		if !validEmail(email) {
			http.Error(w, `{"error":"invalid email"}`, http.StatusBadRequest)
			return
		}

		csvMu.Lock()
		defer csvMu.Unlock()

		if lookupRole(cfg.AuthDir, email) != "" {
			if _, err := removeFromCSV(filepath.Join(cfg.AuthDir, "wants-account.csv"), email); err != nil {
				log.Printf("access: remove already-authorized %s from wants-account: %v", email, err)
			}
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprint(w, `{"ok":true,"note":"already authorized"}`)
			return
		}

		canViewPath := filepath.Join(cfg.AuthDir, "can-view.csv")
		if err := appendToCSV(canViewPath, email); err != nil {
			log.Printf("access: approve %s: %v", email, err)
			http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
			return
		}

		wantsPath := filepath.Join(cfg.AuthDir, "wants-account.csv")
		if _, err := removeFromCSV(wantsPath, email); err != nil {
			log.Printf("access: remove from wants-account after approve %s: %v", email, err)
		}

		log.Printf("access: approved %s for viewing", email)
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"ok":true}`)
	}
}

// DenyAccessRequest removes an email from wants-account.csv without granting access.
// Requires "post" role.
func DenyAccessRequest(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if RoleFromContext(r.Context()) != "post" {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}

		email := strings.ToLower(r.PathValue("email"))
		if !validEmail(email) {
			http.Error(w, `{"error":"invalid email"}`, http.StatusBadRequest)
			return
		}

		csvMu.Lock()
		defer csvMu.Unlock()

		wantsPath := filepath.Join(cfg.AuthDir, "wants-account.csv")
		removed, err := removeFromCSV(wantsPath, email)
		if err != nil {
			log.Printf("access: deny %s: %v", email, err)
			http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
			return
		}
		if !removed {
			http.Error(w, `{"error":"not found"}`, http.StatusNotFound)
			return
		}

		log.Printf("access: denied %s", email)
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"ok":true}`)
	}
}
