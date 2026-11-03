CREATE TABLE feeds (
	id            INTEGER PRIMARY KEY,
	url           TEXT NOT NULL UNIQUE,
	title         TEXT NOT NULL DEFAULT '',
	site_url      TEXT NOT NULL DEFAULT '',
	category      TEXT NOT NULL DEFAULT '',
	etag          TEXT NOT NULL DEFAULT '',
	last_modified TEXT NOT NULL DEFAULT '',
	last_fetched  INTEGER NOT NULL DEFAULT 0,
	error         TEXT NOT NULL DEFAULT ''
);

CREATE TABLE entries (
	id        INTEGER PRIMARY KEY,
	feed_id   INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
	guid      TEXT NOT NULL,
	url       TEXT NOT NULL DEFAULT '',
	title     TEXT NOT NULL DEFAULT '',
	author    TEXT NOT NULL DEFAULT '',
	content   TEXT NOT NULL DEFAULT '',
	published INTEGER NOT NULL DEFAULT 0,
	read      INTEGER NOT NULL DEFAULT 0,
	starred   INTEGER NOT NULL DEFAULT 0,
	UNIQUE (feed_id, guid)
);

CREATE INDEX entries_timeline ON entries (published DESC, id DESC);
CREATE INDEX entries_feed_timeline ON entries (feed_id, published DESC, id DESC);
