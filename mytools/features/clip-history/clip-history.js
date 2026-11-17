const KEY = 'clipHistory';
const MAX = 5;

// 최근 복사한 텍스트, 최신순.
// storage.session(메모리 전용)이라 브라우저를 닫으면 지워진다 — 복사한 비밀번호 등이 디스크에 남지 않게
export async function recentClips() {
  const { [KEY]: list = [] } = await chrome.storage.session.get(KEY);
  return list;
}

export async function rememberClip(text) {
  if (!text?.trim()) return;
  await chrome.storage.session.set({ [KEY]: pushClip(await recentClips(), text) });
}

// 같은 텍스트는 맨 위로 올린다. 이어 붙이기 결과는 이전 항목을 포함하므로 그 항목을 대체한다.
// shortcut: "foo" 다음 "foobar"를 복사해도 "foo"가 사라진다, 문제되면 이어 붙이기 경로에서만 대체
export function pushClip(list, text) {
  const rest = list.filter((t) => !text.startsWith(t.trimEnd()));
  return [text, ...rest].slice(0, MAX);
}
