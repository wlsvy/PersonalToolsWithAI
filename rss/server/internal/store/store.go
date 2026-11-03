// Package store defines the domain types and the storage interface.
// Implementations live in subpackages (e.g. store/sqlite).
package store

import (
	"context"
	"errors"
)

var (
	ErrNotFound  = errors.New("not found")
	ErrDuplicate = errors.New("duplicate")
)

type Feed struct {
	ID           int64  `json:"id"`
	URL          string `json:"url"`
	Title        string `json:"title"`
	SiteURL      string `json:"siteUrl"`
	Category     string `json:"category"`
	LastFetched  int64  `json:"lastFetched"`
	Error        string `json:"error"`
	Unread       int    `json:"unread"`
	ETag         string `json:"-"`
	LastModified string `json:"-"`
}

// FeedMeta is what a fetch writes back to a feed.
type FeedMeta struct {
	Title        string
	SiteURL      string
	ETag         string
	LastModified string
	LastFetched  int64
	Error        string
}

type Entry struct {
	ID        int64  `json:"id"`
	FeedID    int64  `json:"feedId"`
	GUID      string `json:"-"`
	URL       string `json:"url"`
	Title     string `json:"title"`
	Author    string `json:"author"`
	Published int64  `json:"published"`
	Read      bool   `json:"read"`
	Starred   bool   `json:"starred"`
	Content   string `json:"content,omitempty"`
}

// Cursor points at the last entry of a page; the next page starts after it.
type Cursor struct {
	Published int64
	ID        int64
}

type EntryFilter struct {
	FeedID  *int64
	Unread  bool
	Starred bool
	Limit   int
	Before  *Cursor
}

type UnreadCount struct {
	FeedID int64 `json:"feedId"`
	Count  int   `json:"count"`
}

type Store interface {
	ListFeeds(ctx context.Context) ([]Feed, error)
	GetFeed(ctx context.Context, id int64) (Feed, error)
	AddFeed(ctx context.Context, url, category string) (Feed, error)
	DeleteFeed(ctx context.Context, id int64) error
	UpdateFeedMeta(ctx context.Context, id int64, m FeedMeta) error
	UpsertEntries(ctx context.Context, feedID int64, es []Entry) error
	ListEntries(ctx context.Context, f EntryFilter) ([]Entry, error)
	GetEntry(ctx context.Context, id int64) (Entry, error)
	UpdateEntry(ctx context.Context, id int64, read, starred *bool) error
	MarkAllRead(ctx context.Context, feedID *int64) error
	UnreadCounts(ctx context.Context) ([]UnreadCount, int, error)
	Close() error
}
