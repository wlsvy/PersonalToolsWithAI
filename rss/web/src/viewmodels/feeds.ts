import { computed, ref } from "vue"

import type { Client, Feed } from "../api/client"
import { useAsync } from "./async"

export function useFeedsVM(client: Client) {
  const feeds = ref<Feed[]>([])
  const { loading, error, run } = useAsync()
  const totalUnread = computed(() => feeds.value.reduce((n, f) => n + f.unread, 0))

  const load = () =>
    run(async () => {
      feeds.value = await client.feeds()
    })

  const add = (url: string, category?: string) =>
    run(async () => {
      const f = await client.addFeed(url.trim(), category?.trim() || undefined)
      feeds.value = [...feeds.value, f]
      return f
    })

  const remove = (id: number) =>
    run(async () => {
      await client.deleteFeed(id)
      feeds.value = feeds.value.filter((f) => f.id !== id)
    })

  const refresh = (id: number) =>
    run(async () => {
      const updated = await client.refreshFeed(id)
      feeds.value = feeds.value.map((f) => (f.id === id ? updated : f))
    })

  return { feeds, totalUnread, loading, error, load, add, remove, refresh }
}
