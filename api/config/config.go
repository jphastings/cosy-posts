package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// Config holds the server configuration loaded from YAML.
type Config struct {
	Listen  string `yaml:"listen"`
	LogFile string `yaml:"log_file"`

	Directories struct {
		Content string `yaml:"content"`
		Site    string `yaml:"site"`
		Uploads string `yaml:"uploads"`
		Auth    string `yaml:"auth"`
	} `yaml:"directories"`

	Site struct {
		Name         string `yaml:"name"`
		BuildCommand string `yaml:"build_command"`
		BaseURL      string `yaml:"base_url"`
	} `yaml:"site"`

	Email struct {
		From         string `yaml:"from"`
		ResendAPIKey string `yaml:"resend_api_key"`
	} `yaml:"email"`

	Dir string `yaml:"-"` // resolved directory of the config file itself
}

// Convenience accessors matching existing usage.
func (c *Config) ContentDir() string  { return c.Directories.Content }
func (c *Config) SiteDir() string     { return c.Directories.Site }
func (c *Config) TUSUploadDir() string { return c.Directories.Uploads }
func (c *Config) AuthDir() string     { return c.Directories.Auth }
func (c *Config) SiteName() string    { return c.Site.Name }
func (c *Config) RebuildCmd() string  { return c.Site.BuildCommand }
func (c *Config) BaseURL() string     { return c.Site.BaseURL }
func (c *Config) ResendAPIKey() string { return c.Email.ResendAPIKey }
func (c *Config) FromEmail() string   { return c.Email.From }

// Load reads and parses a YAML config file at the given path.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config file: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parsing config file: %w", err)
	}

	if cfg.Listen == "" {
		cfg.Listen = ":8080"
	}
	if cfg.Directories.Content == "" {
		cfg.Directories.Content = "./content"
	}
	if cfg.Directories.Uploads == "" {
		cfg.Directories.Uploads = "./uploads"
	}
	if cfg.Directories.Auth == "" {
		cfg.Directories.Auth = "./auth"
	}
	if cfg.Directories.Site == "" {
		cfg.Directories.Site = "./site"
	}

	// Resolve relative paths against the config file's directory.
	configDir, _ := filepath.Abs(filepath.Dir(path))
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
