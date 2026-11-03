<script setup lang="ts">
import { onMounted } from "vue"
import { useRoute } from "vue-router"

import { useClient } from "../inject"
import { useEntryVM } from "../viewmodels/entry"

const vm = useEntryVM(useClient(), Number(useRoute().params.id))
const date = (s: number) => new Date(s * 1000).toLocaleString()

onMounted(vm.load)
</script>

<template>
  <p v-if="vm.error.value" class="error" role="alert">{{ vm.error.value }}</p>
  <article v-if="vm.entry.value">
    <h1>{{ vm.entry.value.title }}</h1>
    <p class="meta">{{ date(vm.entry.value.published) }} {{ vm.entry.value.author }}</p>
    <div class="row">
      <button @click="vm.toggleStar">{{ vm.entry.value.starred ? "★ 즐겨찾기 해제" : "☆ 즐겨찾기" }}</button>
      <button @click="vm.markUnread" :disabled="!vm.entry.value.read">안 읽음으로</button>
      <a v-if="vm.entry.value.url" :href="vm.entry.value.url" target="_blank" rel="noopener noreferrer"><button>원문 열기</button></a>
    </div>
    <!-- content is sanitized by the server (bluemonday) and guarded by the page CSP -->
    <div class="content" v-html="vm.entry.value.content"></div>
  </article>
</template>
