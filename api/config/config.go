package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/viper"
)

// Config holds the server configuration loaded from YAML or environment variables.
type Config struct {
	Listen     string `mapstructure:"listen"`
	ContentDir string `mapstructure:"content_dir"`
	AuthDir    string `mapstructure:"auth_dir"`

	Site struct {
		Name         string `mapstructure:"name"`
		BuildCommand string `mapstructure:"build_command"`
		Directory    string `mapstructure:"directory"`
	} `mapstructure:"site"`

	Email struct {
		From         string `mapstructure:"from"`
		ResendAPIKey string `mapstructure:"resend_api_key"`
	} `mapstructure:"email"`

	Dir       string `mapstructure:"-"` // resolved directory of the config file itself
	UploadDir string `mapstructure:"-"` // temporary directory for TUS uploads
}

// Convenience accessors matching existing usage.
func (c *Config) SiteDir() string      { return c.Site.Directory }
func (c *Config) TUSUploadDir() string { return c.UploadDir }
func (c *Config) SiteName() string     { return c.Site.Name }
func (c *Config) RebuildCmd() string   { return c.Site.BuildCommand }
func (c *Config) ResendAPIKey() string { return c.Email.ResendAPIKey }
func (c *Config) FromEmail() string    { return c.Email.From }

// HasExternalSite returns true when both a build command and site directory are configured.
func (c *Config) HasExternalSite() bool {
	return c.Site.BuildCommand != "" && c.Site.Directory != ""
}

// Load reads config from a YAML file (if provided) and/or environment variables.
// Environment variables use the COSY_ prefix with underscores for nesting:
//
//	COSY_LISTEN, COSY_CONTENT_DIR, COSY_AUTH_DIR,
//	COSY_SITE_NAME, COSY_SITE_BUILD_COMMAND, COSY_SITE_DIRECTORY,
//	COSY_EMAIL_FROM, COSY_EMAIL_RESEND_API_KEY
func Load(path string) (*Config, error) {
	v := viper.New()

	// Defaults.
	v.SetDefault("listen", ":8080")
	v.SetDefault("content_dir", "./content")

	// Environment variable binding.
	v.SetEnvPrefix("COSY")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

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

	// Validate required fields.
	if cfg.Email.From == "" {
		return nil, fmt.Errorf("email.from (COSY_EMAIL_FROM) is required")
	}
	if cfg.Email.ResendAPIKey == "" {
		return nil, fmt.Errorf("email.resend_api_key (COSY_EMAIL_RESEND_API_KEY) is required")
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

// resolve makes a relative path absolute against base. Absolute paths pass through.
func resolve(base, path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(base, path)
}
