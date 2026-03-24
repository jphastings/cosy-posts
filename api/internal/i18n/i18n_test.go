package i18n

import (
	"testing"

	"github.com/nicksnyder/go-i18n/v2/i18n"
)

func TestT_English(t *testing.T) {
	loc := NewLocalizer("en")
	got := T(loc, "AboutThisSite")
	if got != "About this site" {
		t.Errorf("T(en, AboutThisSite) = %q, want %q", got, "About this site")
	}
}

func TestT_FallbackToEnglish(t *testing.T) {
	loc := NewLocalizer("xx") // unknown language
	got := T(loc, "Close")
	if got != "Close" {
		t.Errorf("T(xx, Close) = %q, want %q", got, "Close")
	}
}

func TestT_MissingKeyReturnsID(t *testing.T) {
	loc := NewLocalizer("en")
	got := T(loc, "NonExistentKey")
	if got != "NonExistentKey" {
		t.Errorf("T(en, NonExistentKey) = %q, want %q", got, "NonExistentKey")
	}
}

func TestPluralization(t *testing.T) {
	loc := NewLocalizer("en")

	one, _ := loc.Localize(&i18n.LocalizeConfig{
		MessageID:   "NotifyNewPost",
		PluralCount: 1,
		TemplateData: map[string]string{
			"Authors": "Alice",
			"Site":    "My Site",
		},
	})
	if one != "There is a new post from Alice on My Site." {
		t.Errorf("singular = %q", one)
	}

	other, _ := loc.Localize(&i18n.LocalizeConfig{
		MessageID:   "NotifyNewPost",
		PluralCount: 3,
		TemplateData: map[string]string{
			"Authors": "Alice, Bob, and Charlie",
			"Site":    "My Site",
		},
	})
	if other != "There are new posts from Alice, Bob, and Charlie on My Site." {
		t.Errorf("plural = %q", other)
	}
}

func TestTemplateData(t *testing.T) {
	loc := NewLocalizer("en")
	got, _ := loc.Localize(&i18n.LocalizeConfig{
		MessageID:   "EmailLinksExpire",
		TemplateData: map[string]any{"Minutes": 30},
	})
	if got != "These links expire in 30 minutes." {
		t.Errorf("EmailLinksExpire = %q", got)
	}
}
