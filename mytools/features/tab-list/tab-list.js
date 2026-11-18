// 현재 창에 열린 탭의 id, 제목, URL, 브라우저에서 선택(Ctrl/Shift+클릭)됐는지 여부
export async function listTabs() {
  const tabs = await chrome.tabs.query({ currentWindow: true });
  return tabs.map(({ id, title, url, highlighted }) => ({ id, title, url, highlighted }));
}

// 한 줄에 URL 하나
export const urlList = (tabs) => tabs.map((t) => t.url).join('\n');

// - [제목](URL) 목록. 제목의 []\ 와 URL의 ()·공백이 링크 문법을 깨지 않게 이스케이프한다
export const markdownList = (tabs) =>
  tabs
    .map(({ title, url }) => {
      const text = (title || url).replace(/[\\[\]]/g, '\\$&');
      const href = url.replace(/[()\s]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0'));
      return `- [${text}](${href})`;
    })
    .join('\n');
