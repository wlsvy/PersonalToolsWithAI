<script setup lang="ts">
import { onMounted, ref } from "vue"

import { useClient } from "../inject"
import { useFeedsVM } from "../viewmodels/feeds"

const vm = useFeedsVM(useClient())
const url = ref("")
const category = ref("")

async function add() {
  if (await vm.add(url.value, category.value)) {
    url.value = ""
    category.value = ""
  }
}

function remove(id: number, name: string) {
  if (confirm(`"${name}" 피드를 삭제할까요?`)) vm.remove(id)
}

onMounted(vm.load)
</script>

<template>
  <form class="row" @submit.prevent="add">
    <input v-model="url" type="url" placeholder="피드 URL" aria-label="피드 URL" required />
    <input v-model="category" placeholder="카테고리 (선택)" aria-label="카테고리" />
    <button class="primary" :disabled="vm.loading.value">추가</button>
  </form>
  <p v-if="vm.error.value" class="error" role="alert">{{ vm.error.value }}</p>

  <ul class="list">
    <li>
      <RouterLink class="main" :to="{ name: 'entries' }"><span class="title">모든 글</span></RouterLink>
      <span class="badge">{{ vm.totalUnread.value }}</span>
    </li>
    <li v-for="f in vm.feeds.value" :key="f.id">
      <RouterLink class="main" :to="{ name: 'entries', query: { feed: f.id, title: f.title || f.url } }">
        <span class="title">{{ f.title || f.url }}</span>
        <span class="meta">
          {{ f.category }}
          <span v-if="f.error" class="error" :title="f.error">· 가져오기 실패</span>
        </span>
      </RouterLink>
      <span class="badge" aria-label="안 읽은 글">{{ f.unread }}</span>
      <button class="icon" aria-label="새로고침" @click="vm.refresh(f.id)">↻</button>
      <button class="icon" aria-label="삭제" @click="remove(f.id, f.title || f.url)">✕</button>
    </li>
  </ul>
</template>
