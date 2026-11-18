// 현재 창에 열린 탭의 id, 제목, URL
export async function listTabs() {
  const tabs = await chrome.tabs.query({ currentWindow: true });
  return tabs.map(({ id, title, url }) => ({ id, title, url }));
}
