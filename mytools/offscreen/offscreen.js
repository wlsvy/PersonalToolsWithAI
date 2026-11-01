// offscreen 문서는 포커스가 없어 navigator.clipboard 대신 execCommand를 쓴다
chrome.runtime.onMessage.addListener(({ type, text }, _sender, sendResponse) => {
  if (type !== 'copy') return;
  const ta = document.createElement('textarea');
  ta.value = text;
  document.body.append(ta);
  ta.select();
  document.execCommand('copy');
  ta.remove();
  sendResponse();
});
