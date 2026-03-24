package i18n

import (
	"embed"

	"github.com/BurntSushi/toml"
	"github.com/nicksnyder/go-i18n/v2/i18n"
	"golang.org/x/text/language"
)

//go:embed locales/*.toml
var localeFS embed.FS

var bundle *i18n.Bundle

func init() {
	bundle = i18n.NewBundle(language.English)
	bundle.RegisterUnmarshalFunc("toml", toml.Unmarshal)
	entries, _ := localeFS.ReadDir("locales")
	for _, e := range entries {
		bundle.LoadMessageFileFS(localeFS, "locales/"+e.Name())
	}
}

// NewLocalizer creates a localizer for the given language tags.
func NewLocalizer(langs ...string) *i18n.Localizer {
	return i18n.NewLocalizer(bundle, langs...)
}

// T is a convenience for simple message lookup (no interpolation or pluralization).
func T(loc *i18n.Localizer, id string) string {
	s, err := loc.Localize(&i18n.LocalizeConfig{MessageID: id})
	if err != nil {
		return id
	}
	return s
}
