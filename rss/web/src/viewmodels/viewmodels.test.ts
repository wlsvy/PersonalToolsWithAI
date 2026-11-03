import { describe, expect, it, vi } from "vitest"

import type { Client, Entry } from "../api/client"
import { useEntriesVM } from "./entries"
import { useEntryVM } from "./entry"
import { useFeedsVM } from "./feeds"

const entry = (id: number, over: Partial<Entry> = {}): Entry => ({
  id, feedId: 1, url: "", title: `e${id}`, author: "", published: id, read: false, starred: false, ...over,
})

function fakeClient(over: Partial<Client> = {}): Client {
  return {
    feeds: vi.fn(async () => []),
    addFeed: vi.fn(),
    deleteFeed: vi.fn(async () => undefined),
    refreshFeed: vi.fn(),
    entries: vi.fn(),
    entry: vi.fn(),
    updateEntry: vi.fn(async () => undefined),
    readAll: vi.fn(async () => undefined),
    unread: vi.fn(),
    ...over,
  } as Client
}

describe("useEntriesVM", () => {
  it("pages with the cursor and toggles state locally", async () => {
    const entries = vi.fn()
      .mockResolvedValueOnce({ entries: [entry(2)], next: "2:2" })
      .mockResolvedValueOnce({ entries: [entry(1)], next: null })
    const client = fakeClient({ entries })
    const vm = useEntriesVM(client, { feed: 1 })

    await vm.load()
    await vm.loadMore()
    expect(entries).toHaveBeenLastCalledWith({ feed: 1, before: "2:2" })
    expect(vm.entries.value.map((e) => e.id)).toEqual([2, 1])
    expect(vm.next.value).toBeNull()

    await vm.toggleStar(vm.entries.value[0]!)
    expect(client.updateEntry).toHaveBeenCalledWith(2, { starred: true })
    expect(vm.entries.value[0]!.starred).toBe(true)
  })

  it("clears the unread list after mark all read", async () => {
    const client = fakeClient({ entries: vi.fn(async () => ({ entries: [entry(1)], next: null })) })
    const vm = useEntriesVM(client, { unread: true })
    await vm.load()
    await vm.markAllRead()
    expect(client.readAll).toHaveBeenCalledWith(undefined)
    expect(vm.entries.value).toEqual([])
  })
})

describe("useEntryVM", () => {
  it("marks an unread entry read on load", async () => {
    const client = fakeClient({ entry: vi.fn(async () => entry(5, { content: "<p>x</p>" })) })
    const vm = useEntryVM(client, 5)
    await vm.load()
    expect(client.updateEntry).toHaveBeenCalledWith(5, { read: true })
    expect(vm.entry.value?.read).toBe(true)
  })
})

describe("useFeedsVM", () => {
  it("exposes errors instead of throwing", async () => {
    const vm = useFeedsVM(fakeClient({ feeds: vi.fn(async () => { throw new Error("offline") }) }))
    await vm.load()
    expect(vm.error.value).toBe("offline")
    expect(vm.loading.value).toBe(false)
  })
})
