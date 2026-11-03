import { ref } from "vue"

import { loadSettings, saveSettings } from "../config/settings"

export function useSettingsVM(storage?: Storage) {
  const initial = loadSettings(storage)
  const serverUrl = ref(initial.serverUrl)
  const token = ref(initial.token)
  const saved = ref<boolean | null>(null)

  function save() {
    saved.value = saveSettings({ serverUrl: serverUrl.value, token: token.value }, storage)
  }

  return { serverUrl, token, saved, save }
}
