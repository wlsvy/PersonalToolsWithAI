// Keys are documented in rss/docs/config.ai.md; keep both in sync.
export interface Settings {
  /** Empty = same origin (the Go server serves this app). */
  serverUrl: string
  token: string
}

const KEYS = { serverUrl: "rss.serverUrl", token: "rss.token" } as const

// Storage can be missing or throw (private mode, blocked site data); fall back to empty values.
function safeStorage(): Storage | undefined {
  try {
    return globalThis.localStorage
  } catch {
    return undefined
  }
}

export function loadSettings(storage: Storage | undefined = safeStorage()): Settings {
  const read = (key: string) => {
    try {
      return storage?.getItem(key) ?? ""
    } catch {
      return ""
    }
  }
  return { serverUrl: read(KEYS.serverUrl), token: read(KEYS.token) }
}

export function saveSettings(s: Settings, storage: Storage | undefined = safeStorage()): boolean {
  try {
    if (!storage) return false
    storage.setItem(KEYS.serverUrl, s.serverUrl.trim())
    storage.setItem(KEYS.token, s.token.trim())
    return true
  } catch {
    return false
  }
}
