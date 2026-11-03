// Package feed fetches, parses and sanitizes feeds, then stores them.
package feed

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/microcosm-cc/bluemonday"
	"github.com/mmcdole/gofeed"

	"rss-server/internal/config"
	"rss-server/internal/store"
)

type Fetcher struct {
	store       store.Store
	client      *http.Client
	userAgent   string
	maxBytes    int64
	concurrency int
	policy      *bluemonday.Policy
	now         func() time.Time
}

func New(st store.Store, cfg config.Config) *Fetcher {
	return &Fetcher{
		store:       st,
		client:      &http.Client{Timeout: cfg.FetchTimeout},
		userAgent:   cfg.UserAgent,
		maxBytes:    cfg.MaxFeedBytes,
		concurrency: cfg.FetchConcurrency,
		policy:      bluemonday.UGCPolicy(),
		now:         time.Now,
	}
}

// Run refreshes all feeds now and then every interval until ctx is done.
func (f *Fetcher) Run(ctx context.Context, interval time.Duration) {
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		f.RefreshAll(ctx)
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// RefreshAll refreshes every feed with bounded concurrency.
func (f *Fetcher) RefreshAll(ctx context.Context) {
	feeds, err := f.store.ListFeeds(ctx)
	if err != nil {
		slog.Error("list feeds", "err", err)
		return
	}
	sem := make(chan struct{}, f.concurrency)
	var wg sync.WaitGroup
	for _, fd := range feeds {
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer func() { <-sem; wg.Done() }()
			if _, err := f.Refresh(ctx, fd.ID); err != nil {
				slog.Error("refresh feed", "id", fd.ID, "err", err)
			}
		}()
	}
	wg.Wait()
}

// Refresh fetches one feed. Fetch/parse failures are recorded on the feed's
// error field; only storage errors are returned.
func (f *Fetcher) Refresh(ctx context.Context, id int64) (store.Feed, error) {
	fd, err := f.store.GetFeed(ctx, id)
	if err != nil {
		return fd, err
	}
	meta := store.FeedMeta{
		Title: fd.Title, SiteURL: fd.SiteURL,
		ETag: fd.ETag, LastModified: fd.LastModified,
		LastFetched: f.now().Unix(),
	}
	entries, err := f.fetch(ctx, fd, &meta)
	if err != nil {
		meta.Error = err.Error()
		slog.Warn("fetch feed", "url", fd.URL, "err", err)
	}
	if len(entries) > 0 {
		if err := f.store.UpsertEntries(ctx, id, entries); err != nil {
			return fd, err
		}
	}
	if err := f.store.UpdateFeedMeta(ctx, id, meta); err != nil {
		return fd, err
	}
	return f.store.GetFeed(ctx, id)
}

// fetch returns parsed entries and fills meta; nil entries on 304.
func (f *Fetcher) fetch(ctx context.Context, fd store.Feed, meta *store.FeedMeta) ([]store.Entry, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fd.URL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", f.userAgent)
	if fd.ETag != "" {
		req.Header.Set("If-None-Match", fd.ETag)
	}
	if fd.LastModified != "" {
		req.Header.Set("If-Modified-Since", fd.LastModified)
	}
	resp, err := f.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotModified {
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("http status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, f.maxBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(body)) > f.maxBytes {
		return nil, errors.New("feed exceeds size limit")
	}
	parsed, err := gofeed.NewParser().ParseString(string(body))
	if err != nil {
		return nil, err
	}

	meta.Title = parsed.Title
	meta.SiteURL = parsed.Link
	meta.ETag = resp.Header.Get("ETag")
	meta.LastModified = resp.Header.Get("Last-Modified")
	now := f.now().Unix()
	entries := make([]store.Entry, 0, len(parsed.Items))
	for _, it := range parsed.Items {
		entries = append(entries, f.toEntry(it, now))
	}
	return entries, nil
}

func (f *Fetcher) toEntry(it *gofeed.Item, now int64) store.Entry {
	published := now
	switch {
	case it.PublishedParsed != nil:
		published = it.PublishedParsed.Unix()
	case it.UpdatedParsed != nil:
		published = it.UpdatedParsed.Unix()
	}
	content := it.Content
	if content == "" {
		content = it.Description
	}
	author := ""
	if it.Author != nil {
		author = it.Author.Name
	} else if len(it.Authors) > 0 && it.Authors[0] != nil {
		author = it.Authors[0].Name
	}
	return store.Entry{
		GUID:      guid(it, published),
		URL:       it.Link,
		Title:     it.Title,
		Author:    author,
		Content:   f.policy.Sanitize(content),
		Published: published,
	}
}

// guid falls back to link, then a hash of title+published, so dedupe still works
// for feeds that omit GUIDs.
func guid(it *gofeed.Item, published int64) string {
	if it.GUID != "" {
		return it.GUID
	}
	if it.Link != "" {
		return it.Link
	}
	sum := sha256.Sum256([]byte(it.Title + "\x00" + strconv.FormatInt(published, 10)))
	return "sha256:" + hex.EncodeToString(sum[:])
}
