package config

import (
	"fmt"
	"os"

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

	return &cfg, nil
}
