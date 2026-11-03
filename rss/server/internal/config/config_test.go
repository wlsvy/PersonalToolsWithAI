package config

import (
	"testing"
	"time"
)

func env(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestDefaults(t *testing.T) {
	c, err := Load(env(map[string]string{"RSS_TOKEN": "t"}))
	if err != nil {
		t.Fatal(err)
	}
	if c.Addr != "127.0.0.1:8080" || c.Interval != 30*time.Minute || c.PageMax != 200 {
		t.Fatalf("unexpected defaults: %+v", c)
	}
}

func TestInvalid(t *testing.T) {
	cases := map[string]map[string]string{
		"missing token":   {},
		"bad duration":    {"RSS_TOKEN": "t", "RSS_INTERVAL": "soon"},
		"bad int":         {"RSS_TOKEN": "t", "RSS_PAGE_MAX": "-1"},
		"default too big": {"RSS_TOKEN": "t", "RSS_PAGE_DEFAULT": "300"},
	}
	for name, m := range cases {
		if _, err := Load(env(m)); err == nil {
			t.Errorf("%s: expected error", name)
		}
	}
}
