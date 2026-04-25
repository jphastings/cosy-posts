package config

import (
	"fmt"
	"net/mail"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/spf13/viper"
)

var resendKeyPattern = regexp.MustCompile(`^re_[A-Za-z0-9_]{20,}$`)

// Config holds the server configuration loaded from YAML or environment variables.
type Config struct {
	Listen     string `mapstructure:"listen"`
	ContentDir string `mapstructure:"content_dir"`
	AuthDir    string `mapstructure:"auth_dir"`

	Site struct {
		Name            string `mapstructure:"name"`
		URL             string `mapstructure:"url"`
		CacheTTLMinutes int    `mapstructure:"cache_ttl_minutes"`
		BuildCommand    string `mapstructure:"build_command"`
		Directory       string `mapstructure:"directory"`
	} `mapstructure:"site"`

	Email struct {
		From                   string `mapstructure:"from"`
		ResendAPIKey           string `mapstructure:"resend_api_key"`
		NotificationWindowMins int    `mapstructure:"notification_window_minutes"`
		SendPostPreview        bool   `mapstructure:"send_post_preview"`
	} `mapstructure:"email"`

	RSSSecret string `mapstructure:"rss_secret"`

	Dir       string `mapstructure:"-"` // resolved directory of the config file itself
	UploadDir string `mapstructure:"-"` // temporary directory for TUS uploads
}

// Convenience accessors matching existing usage.
func (c *Config) SiteDir() string      { return c.Site.Directory }
func (c *Config) TUSUploadDir() string { return c.UploadDir }
func (c *Config) SiteName() string     { return c.Site.Name }
func (c *Config) SiteURL() string      { return c.Site.URL }
func (c *Config) CacheTTLSeconds() int { return c.Site.CacheTTLMinutes * 60 }
func (c *Config) RebuildCmd() string   { return c.Site.BuildCommand }
func (c *Config) ResendAPIKey() string { return c.Email.ResendAPIKey }
func (c *Config) FromEmail() string {
	if c.Site.Name != "" {
		return c.Site.Name + " <" + c.Email.From + ">"
	}
	return c.Email.From
}
func (c *Config) NotificationWindowMinutes() int { return c.Email.NotificationWindowMins }
func (c *Config) SendPostPreview() bool          { return c.Email.SendPostPreview }

// HasExternalSite returns true when both a build command and site directory are configured.
func (c *Config) HasExternalSite() bool {
	return c.Site.BuildCommand != "" && c.Site.Directory != ""
}

// Load reads config from a YAML file (if provided) and/or environment variables.
// Environment variables use the COSY_ prefix with underscores for nesting:
//
//	COSY_LISTEN, COSY_CONTENT_DIR, COSY_AUTH_DIR,
//	COSY_SITE_NAME, COSY_SITE_URL, COSY_SITE_BUILD_COMMAND, COSY_SITE_DIRECTORY,
//	COSY_EMAIL_FROM, COSY_EMAIL_RESEND_API_KEY,
//	COSY_EMAIL_NOTIFICATION_WINDOW_MINUTES, COSY_EMAIL_SEND_POST_PREVIEW,
//	COSY_RSS_SECRET
func Load(path string) (*Config, error) {
	v := viper.New()

	// Defaults.
	v.SetDefault("listen", ":8080")
	v.SetDefault("content_dir", "./content")
	v.SetDefault("email.notification_window_minutes", 10)
	v.SetDefault("email.send_post_preview", false)
	v.SetDefault("site.cache_ttl_minutes", 10)

	// Environment variable binding.
	v.SetEnvPrefix("COSY")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	// Explicit bindings where AutomaticEnv can't distinguish dots
	// (nesting) from underscores (in key names).
	v.BindEnv("content_dir", "COSY_CONTENT_DIR")
	v.BindEnv("auth_dir", "COSY_AUTH_DIR")
	v.BindEnv("email.from", "COSY_EMAIL_FROM")
	v.BindEnv("email.resend_api_key", "COSY_EMAIL_RESEND_API_KEY")
	v.BindEnv("email.notification_window_minutes", "COSY_EMAIL_NOTIFICATION_WINDOW_MINUTES")
	v.BindEnv("email.send_post_preview", "COSY_EMAIL_SEND_POST_PREVIEW")
	v.BindEnv("site.name", "COSY_SITE_NAME")
	v.BindEnv("site.url", "COSY_SITE_URL")
	v.BindEnv("site.cache_ttl_minutes", "COSY_SITE_CACHE_TTL_MINUTES")
	v.BindEnv("site.build_command", "COSY_SITE_BUILD_COMMAND")
	v.BindEnv("site.directory", "COSY_SITE_DIRECTORY")
	v.BindEnv("rss_secret", "COSY_RSS_SECRET")

	// Load config file if specified.
	if path != "" {
		v.SetConfigFile(path)
		if err := v.ReadInConfig(); err != nil {
			return nil, err
		}
	}

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, err
	}

	if err := cfg.validate(); err != nil {
		return nil, err
	}

	// Resolve relative paths against the config file's directory (or cwd).
	configDir := "."
	if path != "" {
		configDir, _ = filepath.Abs(filepath.Dir(path))
	}
	cfg.Dir = configDir
	cfg.ContentDir = resolve(configDir, cfg.ContentDir)
	if cfg.AuthDir == "" {
		cfg.AuthDir = configDir
	} else {
		cfg.AuthDir = resolve(configDir, cfg.AuthDir)
	}
	if cfg.Site.Directory != "" {
		cfg.Site.Directory = resolve(configDir, cfg.Site.Directory)
	}

	// Create a temporary directory for TUS uploads.
	uploadDir, err := os.MkdirTemp("", "cosy-uploads-*")
	if err != nil {
		return nil, fmt.Errorf("creating upload temp dir: %w", err)
	}
	cfg.UploadDir = uploadDir

	return &cfg, nil
}

func (cfg *Config) validate() error {
	if cfg.Site.Name == "" {
		return fmt.Errorf("site.name (COSY_SITE_NAME) is required")
	}

	u, err := url.Parse(cfg.Site.URL)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return fmt.Errorf("site.url (COSY_SITE_URL) must be a full URL (e.g. https://example.com)")
	}

	if cfg.Site.CacheTTLMinutes < 1 {
		return fmt.Errorf("site.cache_ttl_minutes (COSY_SITE_CACHE_TTL_MINUTES) must be a positive number")
	}

	if _, err := mail.ParseAddress(cfg.Email.From); err != nil {
		return fmt.Errorf("email.from (COSY_EMAIL_FROM) must be a valid email address: %w", err)
	}

	if !resendKeyPattern.MatchString(cfg.Email.ResendAPIKey) {
		return fmt.Errorf("email.resend_api_key (COSY_EMAIL_RESEND_API_KEY) must be a valid Resend API key (re_...)")
	}

	if cfg.RSSSecret != "" && len(cfg.RSSSecret) < 16 {
		return fmt.Errorf("rss_secret (COSY_RSS_SECRET) must be at least 16 characters long")
	}

	if cfg.Email.NotificationWindowMins < 1 {
		return fmt.Errorf("email.notification_window_minutes (COSY_EMAIL_NOTIFICATION_WINDOW_MINUTES) must be a positive number")
	}

	return nil
}

// resolve makes a relative path absolute against base. Absolute paths pass through.
func resolve(base, path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(base, path)
}
