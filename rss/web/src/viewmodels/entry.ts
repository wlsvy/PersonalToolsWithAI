import { ref } from "vue"

import type { Client, Entry } from "../api/client"
import { useAsync } from "./async"

export function useEntryVM(client: Client, id: number) {
  const entry = ref<Entry | null>(null)
  const { loading, error, run } = useAsync()

  /** Loads the entry and marks it read, as opening an entry means reading it. */
  const load = () =>
    run(async () => {
      const e = await client.entry(id)
      if (!e.read) {
        await client.updateEntry(id, { read: true })
        e.read = true
      }
      entry.value = e
    })

  const toggleStar = () =>
    run(async () => {
      if (!entry.value) return
      const starred = !entry.value.starred
      await client.updateEntry(id, { starred })
      entry.value = { ...entry.value, starred }
    })

  const markUnread = () =>
    run(async () => {
      if (!entry.value) return
      await client.updateEntry(id, { read: false })
      entry.value = { ...entry.value, read: false }
    })

  return { entry, loading, error, load, toggleStar, markUnread }
}
