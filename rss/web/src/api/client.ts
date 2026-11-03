// API v1 client (contract: rss/docs/api.ai.md). Only this module knows paths.
import type { Settings } from "../config/settings"

const BASE_PATH = "/api/v1"

export interface Feed {
  id: number
  url: string
  title: string
  siteUrl: string
  category: string
  lastFetched: number
  error: string
  unread: number
}

export interface Entry {
  id: number
  feedId: number
  url: string
  title: string
  author: string
  published: number
  read: boolean
  starred: boolean
  content?: string
}

export interface Page {
  entries: Entry[]
  next: string | null
}

export interface EntryQuery {
  feed?: number
  unread?: boolean
  starred?: boolean
  limit?: number
  before?: string
}

export interface UnreadCounts {
  feeds: { feedId: number; count: number }[]
  total: number
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message)
  }
}

type Fetch = typeof fetch

/** getSettings is read on every request so settings changes apply immediately. */
export function createClient(getSettings: () => Settings, fetchFn: Fetch = (...a) => fetch(...a)) {
  async function request<T>(method: string, path: string, opts: { query?: EntryQuery | Record<string, unknown>; body?: unknown } = {}): Promise<T> {
    const { serverUrl, token } = getSettings()
    const params = new URLSearchParams()
    for (const [k, v] of Object.entries(opts.query ?? {})) {
      if (v === undefined || v === false || v === null) continue
      params.set(k, v === true ? "1" : String(v))
    }
    const qs = params.size > 0 ? `?${params}` : ""
    const headers: Record<string, string> = { Authorization: `Bearer ${token}` }
    if (opts.body !== undefined) headers["Content-Type"] = "application/json"

    const res = await fetchFn(`${serverUrl.replace(/\/$/, "")}${BASE_PATH}${path}${qs}`, {
      method,
      headers,
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
    })
    if (!res.ok) {
      const msg = await res
        .json()
        .then((d: { error?: string }) => d.error)
        .catch(() => undefined)
      throw new ApiError(res.status, msg ?? res.statusText)
    }
    return (res.status === 204 ? undefined : await res.json()) as T
  }

  return {
    feeds: () => request<Feed[]>("GET", "/feeds"),
    addFeed: (url: string, category?: string) => request<Feed>("POST", "/feeds", { body: { url, category } }),
    deleteFeed: (id: number) => request<void>("DELETE", `/feeds/${id}`),
    refreshFeed: (id: number) => request<Feed>("POST", `/feeds/${id}/refresh`),
    entries: (q: EntryQuery = {}) => request<Page>("GET", "/entries", { query: q }),
    entry: (id: number) => request<Entry>("GET", `/entries/${id}`),
    updateEntry: (id: number, fields: { read?: boolean; starred?: boolean }) =>
      request<void>("PATCH", `/entries/${id}`, { body: fields }),
    readAll: (feed?: number) => request<void>("POST", "/entries/read-all", { query: { feed } }),
    unread: () => request<UnreadCounts>("GET", "/unread"),
  }
}

export type Client = ReturnType<typeof createClient>
