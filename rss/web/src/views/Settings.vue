<script setup lang="ts">
import { useRouter } from "vue-router"

import { useSettingsVM } from "../viewmodels/settings"

const vm = useSettingsVM()
const router = useRouter()

function save() {
  vm.save()
  if (vm.saved.value) router.push("/")
}
</script>

<template>
  <h2>설정</h2>
  <form @submit.prevent="save">
    <div class="row">
      <input v-model="vm.token.value" type="password" placeholder="토큰" aria-label="토큰" autocomplete="current-password" required />
    </div>
    <div class="row">
      <input v-model="vm.serverUrl.value" type="url" placeholder="서버 주소 (비우면 현재 주소)" aria-label="서버 주소" />
    </div>
    <button class="primary">저장</button>
    <p v-if="vm.saved.value === false" class="error" role="alert">이 브라우저에서는 설정을 저장할 수 없습니다.</p>
  </form>
</template>
