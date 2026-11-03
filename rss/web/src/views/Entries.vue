<script setup lang="ts">
import { onMounted } from "vue"
import { useRoute } from "vue-router"

import { useClient } from "../inject"
import { useEntriesVM } from "../viewmodels/entries"

const route = useRoute()
const feed = route.query.feed ? Number(route.query.feed) : undefined
const unread = route.query.unread === "1"
const starred = route.query.starred === "1"
const heading = (route.query.title as string) || (unread ? "안 읽은 글" : starred ? "즐겨찾기" : "모든 글")

const vm = useEntriesVM(useClient(), { feed, unread, starred })
const date = (s: number) => new Date(s * 1000).toLocaleDateString()

onMounted(vm.load)
</script>

<template>
  <div class="row">
    <h2 style="flex: 1; margin: 0">{{ heading }}</h2>
    <button @click="vm.markAllRead">모두 읽음</button>
  </div>
  <p v-if="vm.error.value" class="error" role="alert">{{ vm.error.value }}</p>

  <ul class="list">
    <li v-for="e in vm.entries.value" :key="e.id" :class="{ read: e.read }">
      <RouterLink class="main" :to="{ name: 'entry', params: { id: e.id } }">
        <span class="title">{{ e.title || e.url }}</span>
        <span class="meta">{{ date(e.published) }} {{ e.author }}</span>
      </RouterLink>
      <button class="icon" :aria-label="e.read ? '안 읽음으로' : '읽음으로'" @click="vm.toggleRead(e)">
        {{ e.read ? "○" : "●" }}
      </button>
      <button class="icon" :aria-label="e.starred ? '즐겨찾기 해제' : '즐겨찾기'" @click="vm.toggleStar(e)">
        {{ e.starred ? "★" : "☆" }}
      </button>
    </li>
  </ul>
  <p v-if="!vm.loading.value && vm.entries.value.length === 0" class="meta">글이 없습니다.</p>
  <div class="row" style="margin-top: 16px">
    <button v-if="vm.next.value" :disabled="vm.loading.value" @click="vm.loadMore">더 보기</button>
  </div>
</template>
