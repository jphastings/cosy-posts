package config

import (
	"path/filepath"
	"strings"

	"github.com/spf13/viper"
)

// Config holds the server configuration loaded from YAML or environment variables.
type Config struct {
	Listen  string `mapstructure:"listen"`
	LogFile string `mapstructure:"log_file"`

	Directories struct {
		Content string `mapstructure:"content"`
		Site    string `mapstructure:"site"`
		Uploads string `mapstructure:"uploads"`
		Auth    string `mapstructure:"auth"`
	} `mapstructure:"directories"`

	Site struct {
		Name         string `mapstructure:"name"`
		BuildCommand string `mapstructure:"build_command"`
		BaseURL      string `mapstructure:"base_url"`
	} `mapstructure:"site"`

	Email struct {
		From         string `mapstructure:"from"`
		ResendAPIKey string `mapstructure:"resend_api_key"`
	} `mapstructure:"email"`

	Dir string `mapstructure:"-"` // resolved directory of the config file itself
}

// Convenience accessors matching existing usage.
func (c *Config) ContentDir() string   { return c.Directories.Content }
func (c *Config) SiteDir() string      { return c.Directories.Site }
func (c *Config) TUSUploadDir() string { return c.Directories.Uploads }
func (c *Config) AuthDir() string      { return c.Directories.Auth }
func (c *Config) SiteName() string     { return c.Site.Name }
func (c *Config) RebuildCmd() string   { return c.Site.BuildCommand }
func (c *Config) BaseURL() string      { return c.Site.BaseURL }
func (c *Config) ResendAPIKey() string { return c.Email.ResendAPIKey }
func (c *Config) FromEmail() string    { return c.Email.From }

// Load reads config from a YAML file (if provided) and/or environment variables.
// Environment variables use the CHAOS_ prefix with underscores for nesting:
//
//	CHAOS_LISTEN, CHAOS_LOG_FILE,
//	CHAOS_DIRECTORIES_CONTENT, CHAOS_DIRECTORIES_UPLOADS, etc.
//	CHAOS_SITE_NAME, CHAOS_SITE_BUILD_COMMAND, CHAOS_SITE_BASE_URL,
//	CHAOS_EMAIL_FROM, CHAOS_EMAIL_RESEND_API_KEY
func Load(path string) (*Config, error) {
	v := viper.New()

	// Defaults.
	v.SetDefault("listen", ":8080")
	v.SetDefault("directories.content", "./content")
	v.SetDefault("directories.uploads", "./uploads")
	v.SetDefault("directories.auth", "./auth")
	v.SetDefault("directories.site", "./site")

	// Environment variable binding.
	v.SetEnvPrefix("CHAOS")
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

	// Resolve relative paths against the config file's directory (or cwd).
	configDir := "."
	if path != "" {
		configDir, _ = filepath.Abs(filepath.Dir(path))
	}
	cfg.Dir = configDir
	cfg.Directories.Content = resolve(configDir, cfg.Directories.Content)
	cfg.Directories.Site = resolve(configDir, cfg.Directories.Site)
	cfg.Directories.Uploads = resolve(configDir, cfg.Directories.Uploads)
	cfg.Directories.Auth = resolve(configDir, cfg.Directories.Auth)
	if cfg.LogFile != "" {
		cfg.LogFile = resolve(configDir, cfg.LogFile)
	}

	return &cfg, nil
}

// resolve makes a relative path absolute against base. Absolute paths pass through.
func resolve(base, path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(base, path)
}
