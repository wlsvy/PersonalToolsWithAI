// 현재 창에 열린 탭의 제목과 URL
export async function listTabs() {
  const tabs = await chrome.tabs.query({ currentWindow: true });
  return tabs.map(({ title, url }) => ({ title, url }));
}
