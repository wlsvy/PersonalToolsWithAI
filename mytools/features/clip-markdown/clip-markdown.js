const FILES = [
  'features/clip-markdown/vendor/Readability.js',
  'features/clip-markdown/vendor/turndown.js',
  'features/clip-markdown/extract.js',
];

// 현재 탭의 본문을 Markdown(이미지는 ![](url))으로 추출한다. 본문을 못 찾으면 ''.
export async function clipMarkdown(tabId) {
  // 네이버 블로그처럼 본문이 iframe 안에 있는 페이지가 있어 모든 프레임에서 돌리고 가장 긴 결과를 고른다
  const target = { tabId, allFrames: true };
  await chrome.scripting.executeScript({ target, files: FILES });
  const results = await chrome.scripting.executeScript({ target, func: () => extractMarkdown() });
  return results.map((r) => r.result ?? '').reduce((a, b) => (b.length > a.length ? b : a), '');
}
