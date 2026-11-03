import { createRouter, createWebHistory } from "vue-router"

import { loadSettings } from "./config/settings"

export const router = createRouter({
  // History mode relies on the server's SPA fallback (internal/api/static.go).
  history: createWebHistory(),
  routes: [
    { path: "/", name: "feeds", component: () => import("./views/Feeds.vue") },
    { path: "/entries", name: "entries", component: () => import("./views/Entries.vue") },
    { path: "/entry/:id", name: "entry", component: () => import("./views/Entry.vue") },
    { path: "/settings", name: "settings", component: () => import("./views/Settings.vue") },
  ],
})

router.beforeEach((to) => {
  if (to.name !== "settings" && !loadSettings().token) return { name: "settings" }
})
