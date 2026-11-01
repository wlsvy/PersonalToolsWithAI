// 현재 탭의 <html>에 흑백 필터를 넣고 뺀다. 상태는 페이지 DOM에만 있어 새로고침하면 풀린다.
export function toggleGrayscale(tabId) {
  return chrome.scripting.executeScript({
    target: { tabId },
    // shortcut: 페이지가 <html>에 inline filter를 직접 쓰면 덮어쓴다, 문제되면 insertCSS + 전용 class로
    func: () => {
      const s = document.documentElement.style;
      s.filter = s.filter === 'grayscale(1)' ? '' : 'grayscale(1)';
    },
  });
}
