// Package api serves the HTTP API v1 (contract: rss/docs/api.ai.md) and the web app.
package api

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"rss-server/internal/config"
	"rss-server/internal/opml"
	"rss-server/internal/store"
)

const basePath = "/api/v1"

// Refresher is the part of the fetcher the API needs.
type Refresher interface {
	Refresh(ctx context.Context, id int64) (store.Feed, error)
	RefreshAll(ctx context.Context)
}

type server struct {
	store store.Store
	ref   Refresher
	cfg   config.Config
}

func New(st store.Store, ref Refresher, cfg config.Config) http.Handler {
	s := &server{store: st, ref: ref, cfg: cfg}

	api := http.NewServeMux()
	api.HandleFunc("GET /feeds", s.listFeeds)
	api.HandleFunc("POST /feeds", s.addFeed)
	api.HandleFunc("DELETE /feeds/{id}", s.deleteFeed)
	api.HandleFunc("POST /feeds/{id}/refresh", s.refreshFeed)
	api.HandleFunc("GET /entries", s.listEntries)
	api.HandleFunc("GET /entries/{id}", s.getEntry)
	api.HandleFunc("PATCH /entries/{id}", s.updateEntry)
	api.HandleFunc("POST /entries/read-all", s.readAll)
	api.HandleFunc("GET /unread", s.unread)
	api.HandleFunc("GET /opml", s.exportOPML)
	api.HandleFunc("POST /opml", s.importOPML)

	mux := http.NewServeMux()
	mux.Handle(basePath+"/", http.StripPrefix(basePath, s.auth(api)))
	if cfg.WebDir != "" {
		mux.Handle("/", spa(cfg.WebDir))
	}
	return mux
}

func (s *server) auth(next http.Handler) http.Handler {
	want := []byte("Bearer " + s.cfg.Token)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("Authorization")), want) != 1 {
			writeErr(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *server) listFeeds(w http.ResponseWriter, r *http.Request) {
	feeds, err := s.store.ListFeeds(r.Context())
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, feeds)
}

func (s *server) addFeed(w http.ResponseWriter, r *http.Request) {
	var in struct {
		URL      string `json:"url"`
		Category string `json:"category"`
	}
	if !s.decode(w, r, &in) {
		return
	}
	if !validFeedURL(in.URL) {
		writeErr(w, http.StatusBadRequest, "url must be an absolute http(s) URL")
		return
	}
	fd, err := s.store.AddFeed(r.Context(), in.URL, in.Category)
	if err != nil {
		s.fail(w, err)
		return
	}
	if fd, err = s.ref.Refresh(r.Context(), fd.ID); err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, fd)
}

func (s *server) deleteFeed(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	if err := s.store.DeleteFeed(r.Context(), id); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) refreshFeed(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	fd, err := s.ref.Refresh(r.Context(), id)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, fd)
}

func (s *server) listEntries(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	f := store.EntryFilter{
		Unread:  q.Get("unread") == "1",
		Starred: q.Get("starred") == "1",
		Limit:   s.cfg.PageDefault,
	}
	if v := q.Get("feed"); v != "" {
		id, err := strconv.ParseInt(v, 10, 64)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "invalid feed")
			return
		}
		f.FeedID = &id
	}
	if v := q.Get("limit"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 {
			writeErr(w, http.StatusBadRequest, "invalid limit")
			return
		}
		f.Limit = min(n, s.cfg.PageMax)
	}
	if v := q.Get("before"); v != "" {
		c, err := parseCursor(v)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "invalid before")
			return
		}
		f.Before = &c
	}

	limit := f.Limit
	f.Limit++ // one extra row tells whether a next page exists
	entries, err := s.store.ListEntries(r.Context(), f)
	if err != nil {
		s.fail(w, err)
		return
	}
	var next *string
	if len(entries) > limit {
		entries = entries[:limit]
		last := entries[limit-1]
		c := fmt.Sprintf("%d:%d", last.Published, last.ID)
		next = &c
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": entries, "next": next})
}

func (s *server) getEntry(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	e, err := s.store.GetEntry(r.Context(), id)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, e)
}

func (s *server) updateEntry(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var in struct {
		Read    *bool `json:"read"`
		Starred *bool `json:"starred"`
	}
	if !s.decode(w, r, &in) {
		return
	}
	if err := s.store.UpdateEntry(r.Context(), id, in.Read, in.Starred); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) readAll(w http.ResponseWriter, r *http.Request) {
	var feedID *int64
	if v := r.URL.Query().Get("feed"); v != "" {
		id, err := strconv.ParseInt(v, 10, 64)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "invalid feed")
			return
		}
		feedID = &id
	}
	if err := s.store.MarkAllRead(r.Context(), feedID); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) unread(w http.ResponseWriter, r *http.Request) {
	counts, total, err := s.store.UnreadCounts(r.Context())
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"feeds": counts, "total": total})
}

func (s *server) exportOPML(w http.ResponseWriter, r *http.Request) {
	feeds, err := s.store.ListFeeds(r.Context())
	if err != nil {
		s.fail(w, err)
		return
	}
	items := make([]opml.Item, len(feeds))
	for i, f := range feeds {
		items[i] = opml.Item{URL: f.URL, Title: f.Title, SiteURL: f.SiteURL, Category: f.Category}
	}
	w.Header().Set("Content-Type", "text/x-opml; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="subscriptions.opml"`)
	if err := opml.Write(w, "rss subscriptions", items); err != nil {
		slog.Error("write opml", "err", err)
	}
}

func (s *server) importOPML(w http.ResponseWriter, r *http.Request) {
	items, err := opml.Parse(http.MaxBytesReader(w, r.Body, s.cfg.MaxOPMLBytes))
	if err != nil {
		writeErr(w, http.StatusBadRequest, "invalid opml: "+err.Error())
		return
	}
	added, skipped := 0, 0
	for _, it := range items {
		if !validFeedURL(it.URL) {
			skipped++
			continue
		}
		_, err := s.store.AddFeed(r.Context(), it.URL, it.Category)
		switch {
		case errors.Is(err, store.ErrDuplicate):
			skipped++
		case err != nil:
			s.fail(w, err)
			return
		default:
			added++
		}
	}
	if added > 0 {
		// Fetch in the background: an import may hold many feeds.
		go s.ref.RefreshAll(context.WithoutCancel(r.Context()))
	}
	writeJSON(w, http.StatusOK, map[string]int{"added": added, "skipped": skipped})
}

// fail maps store errors to status codes; unknown errors are logged and hidden.
func (s *server) fail(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeErr(w, http.StatusNotFound, "not found")
	case errors.Is(err, store.ErrDuplicate):
		writeErr(w, http.StatusConflict, "already exists")
	default:
		slog.Error("request failed", "err", err)
		writeErr(w, http.StatusInternalServerError, "internal error")
	}
}

func (s *server) decode(w http.ResponseWriter, r *http.Request, v any) bool {
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, s.cfg.MaxJSONBytes)).Decode(v); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json body")
		return false
	}
	return true
}

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "invalid id")
		return 0, false
	}
	return id, true
}

func parseCursor(v string) (store.Cursor, error) {
	p, id, ok := strings.Cut(v, ":")
	if !ok {
		return store.Cursor{}, errors.New("malformed cursor")
	}
	pub, err1 := strconv.ParseInt(p, 10, 64)
	n, err2 := strconv.ParseInt(id, 10, 64)
	if err := errors.Join(err1, err2); err != nil {
		return store.Cursor{}, err
	}
	return store.Cursor{Published: pub, ID: n}, nil
}

func validFeedURL(raw string) bool {
	u, err := url.Parse(raw)
	return err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Host != ""
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("write json", "err", err)
	}
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}
