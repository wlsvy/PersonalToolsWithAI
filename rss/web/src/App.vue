<template>
  <header class="bar">
    <nav>
      <RouterLink to="/">피드</RouterLink>
      <RouterLink :to="{ name: 'entries', query: { unread: '1' } }">안 읽음</RouterLink>
      <RouterLink :to="{ name: 'entries', query: { starred: '1' } }">즐겨찾기</RouterLink>
      <RouterLink to="/settings">설정</RouterLink>
    </nav>
  </header>
  <main>
    <RouterView :key="$route.fullPath" />
  </main>
</template>
