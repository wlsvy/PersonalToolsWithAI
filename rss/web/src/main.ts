import { createApp } from "vue"

import { createClient } from "./api/client"
import App from "./App.vue"
import { loadSettings } from "./config/settings"
import { clientKey } from "./inject"
import { router } from "./router"
import "./style.css"

createApp(App)
  .provide(clientKey, createClient(() => loadSettings()))
  .use(router)
  .mount("#app")
