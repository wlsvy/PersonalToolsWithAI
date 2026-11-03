import { describe, expect, it, vi } from "vitest"

import { ApiError, createClient } from "./client"

function fakeFetch(status: number, body?: unknown) {
  return vi.fn(async (..._args: Parameters<typeof fetch>) =>
    new Response(body === undefined ? null : JSON.stringify(body), { status }),
  )
}

describe("createClient", () => {
  it("sends token, base path and boolean query flags", async () => {
    const f = fakeFetch(200, { entries: [], next: null })
    const c = createClient(() => ({ serverUrl: "https://h/", token: "t" }), f)
    await c.entries({ feed: 3, unread: true, starred: false })
    const [url, init] = f.mock.calls[0]!
    expect(url).toBe("https://h/api/v1/entries?feed=3&unread=1")
    expect((init!.headers as Record<string, string>).Authorization).toBe("Bearer t")
  })

  it("returns undefined for 204 and throws ApiError with server message", async () => {
    const ok = createClient(() => ({ serverUrl: "", token: "t" }), fakeFetch(204))
    await expect(ok.updateEntry(1, { read: true })).resolves.toBeUndefined()

    const bad = createClient(() => ({ serverUrl: "", token: "t" }), fakeFetch(409, { error: "already exists" }))
    await expect(bad.addFeed("https://x")).rejects.toEqual(new ApiError(409, "already exists"))
  })
})
