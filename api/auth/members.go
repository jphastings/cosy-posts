package auth

import (
	"bufio"
	"os"
	"strings"
)

// Member represents a contact-able person parsed from the can-post CSV.
type Member struct {
	Name    string   `json:"name"`
	Methods []Method `json:"methods"`
}

// Method is a single contact method (whatsapp, signal, email).
type Method struct {
	Type string `json:"type"`
	URL  string `json:"url"`
}

// ParseMembers reads a can-post.csv and returns a map of email → Member.
// The CSV format is: email,name,contact_url,...
func ParseMembers(csvPath string) map[string]Member {
	members := make(map[string]Member)
	if csvPath == "" {
		return members
	}

	f, err := os.Open(csvPath)
	if err != nil {
		return members
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		cols := strings.Split(line, ",")
		for i := range cols {
			cols[i] = strings.TrimSpace(cols[i])
		}

		email := cols[0]
		name := email
		if len(cols) > 1 && cols[1] != "" {
			name = cols[1]
		}

		var methods []Method
		for i := 2; i < len(cols); i++ {
			url := cols[i]
			if url == "" {
				continue
			}
			if strings.Contains(url, "wa.me") {
				methods = append(methods, Method{Type: "whatsapp", URL: url})
			} else if strings.Contains(url, "signal.me") {
				methods = append(methods, Method{Type: "signal", URL: url})
			}
		}
		// Email is always available as fallback.
		methods = append(methods, Method{Type: "email", URL: email})

		members[email] = Member{Name: name, Methods: methods}
	}

	return members
}
