package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// Config holds the server configuration loaded from YAML.
type Config struct {
	Listen       string `yaml:"listen"`
	ContentDir   string `yaml:"content_dir"`
	TUSUploadDir string `yaml:"tus_upload_dir"`
	RebuildCmd   string `yaml:"rebuild_command"`
	LogFile      string `yaml:"log_file"`
}

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
	if cfg.ContentDir == "" {
		cfg.ContentDir = "./content"
	}
	if cfg.TUSUploadDir == "" {
		cfg.TUSUploadDir = "./uploads"
	}

	// Resolve relative paths against the config file's directory.
	configDir, _ := filepath.Abs(filepath.Dir(path))
	cfg.ContentDir = resolve(configDir, cfg.ContentDir)
	cfg.TUSUploadDir = resolve(configDir, cfg.TUSUploadDir)
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
