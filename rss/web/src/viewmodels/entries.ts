import { ref } from "vue"

import type { Client, Entry, EntryQuery } from "../api/client"
import { useAsync } from "./async"

/** query selects the list (feed / unread / starred); paging uses the server cursor. */
export function useEntriesVM(client: Client, query: Omit<EntryQuery, "before">) {
  const entries = ref<Entry[]>([])
  const next = ref<string | null>(null)
  const { loading, error, run } = useAsync()

  const load = () =>
    run(async () => {
      const page = await client.entries(query)
      entries.value = page.entries
      next.value = page.next
    })

  const loadMore = () =>
    run(async () => {
      if (!next.value) return
      const page = await client.entries({ ...query, before: next.value })
      entries.value = [...entries.value, ...page.entries]
      next.value = page.next
    })

  const update = (e: Entry, fields: { read?: boolean; starred?: boolean }) =>
    run(async () => {
      await client.updateEntry(e.id, fields)
      entries.value = entries.value.map((x) => (x.id === e.id ? { ...x, ...fields } : x))
    })

  const toggleRead = (e: Entry) => update(e, { read: !e.read })
  const toggleStar = (e: Entry) => update(e, { starred: !e.starred })

  const markAllRead = () =>
    run(async () => {
      await client.readAll(query.feed)
      entries.value = query.unread ? [] : entries.value.map((e) => ({ ...e, read: true }))
      if (query.unread) next.value = null
    })

  return { entries, next, loading, error, load, loadMore, toggleRead, toggleStar, markAllRead }
}
