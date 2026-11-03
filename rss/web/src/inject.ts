import { inject, type InjectionKey } from "vue"

import type { Client } from "./api/client"

export const clientKey: InjectionKey<Client> = Symbol("client")

export function useClient(): Client {
  const c = inject(clientKey)
  if (!c) throw new Error("API client not provided")
  return c
}
