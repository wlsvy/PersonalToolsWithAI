import vue from "@vitejs/plugin-vue"
import { defineConfig } from "vite"

// Dev only: forward API calls to a running rss-server (see docs/config.ai.md).
const devServer = process.env.RSS_DEV_SERVER ?? "http://127.0.0.1:8080"

export default defineConfig({
  plugins: [vue()],
  server: { proxy: { "/api": devServer } },
})
