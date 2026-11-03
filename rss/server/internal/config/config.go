// Package config loads server settings from the environment.
// Keys and defaults are documented in rss/docs/config.ai.md; keep both in sync.
package config

import (
	"errors"
	"fmt"
	"strconv"
	"time"
)

// Version is set at build time with -ldflags "-X rss-server/internal/config.Version=...".
var Version = "dev"

type Config struct {
	Addr              string
	DBPath            string
	Token             string
	Interval          time.Duration
	FetchTimeout      time.Duration
	FetchConcurrency  int
	MaxFeedBytes      int64
	MaxOPMLBytes      int64
	MaxJSONBytes      int64
	PageDefault       int
	PageMax           int
	UserAgent         string
	WebDir            string
	ReadHeaderTimeout time.Duration
	ShutdownTimeout   time.Duration
	AllowPrivateFetch bool
}

// Load reads config through getenv (os.Getenv in production) and validates it.
func Load(getenv func(string) string) (Config, error) {
	l := loader{getenv: getenv}
	c := Config{
		Addr:              l.str("RSS_ADDR", "127.0.0.1:8080"),
		DBPath:            l.str("RSS_DB", "./rss.db"),
		Token:             l.str("RSS_TOKEN", ""),
		Interval:          l.dur("RSS_INTERVAL", 30*time.Minute),
		FetchTimeout:      l.dur("RSS_FETCH_TIMEOUT", 20*time.Second),
		FetchConcurrency:  int(l.num("RSS_FETCH_CONCURRENCY", 4)),
		MaxFeedBytes:      l.num("RSS_MAX_FEED_BYTES", 10<<20),
		MaxOPMLBytes:      l.num("RSS_MAX_OPML_BYTES", 2<<20),
		MaxJSONBytes:      l.num("RSS_MAX_JSON_BYTES", 64<<10),
		PageDefault:       int(l.num("RSS_PAGE_DEFAULT", 50)),
		PageMax:           int(l.num("RSS_PAGE_MAX", 200)),
		UserAgent:         l.str("RSS_USER_AGENT", "rss-server/"+Version),
		WebDir:            l.str("RSS_WEB_DIR", ""),
		ReadHeaderTimeout: l.dur("RSS_READ_HEADER_TIMEOUT", 10*time.Second),
		ShutdownTimeout:   l.dur("RSS_SHUTDOWN_TIMEOUT", 10*time.Second),
		AllowPrivateFetch: l.flag("RSS_ALLOW_PRIVATE_FETCH", false),
	}
	if c.Token == "" {
		l.errs = append(l.errs, errors.New("RSS_TOKEN is required"))
	}
	if c.PageDefault > c.PageMax {
		l.errs = append(l.errs, errors.New("RSS_PAGE_DEFAULT must not exceed RSS_PAGE_MAX"))
	}
	return c, errors.Join(l.errs...)
}

type loader struct {
	getenv func(string) string
	errs   []error
}

func (l *loader) str(key, def string) string {
	if v := l.getenv(key); v != "" {
		return v
	}
	return def
}

func (l *loader) dur(key string, def time.Duration) time.Duration {
	v := l.getenv(key)
	if v == "" {
		return def
	}
	d, err := time.ParseDuration(v)
	if err != nil || d <= 0 {
		l.errs = append(l.errs, fmt.Errorf("%s: invalid duration %q", key, v))
		return def
	}
	return d
}

func (l *loader) flag(key string, def bool) bool {
	v := l.getenv(key)
	if v == "" {
		return def
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		l.errs = append(l.errs, fmt.Errorf("%s: invalid boolean %q", key, v))
		return def
	}
	return b
}

func (l *loader) num(key string, def int64) int64 {
	v := l.getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil || n <= 0 {
		l.errs = append(l.errs, fmt.Errorf("%s: invalid positive integer %q", key, v))
		return def
	}
	return n
}
