// offscreen 문서는 포커스가 없어 navigator.clipboard 대신 execCommand를 쓴다
chrome.runtime.onMessage.addListener(({ type, text }, _sender, sendResponse) => {
  if (type !== 'copy' && type !== 'paste') return;
  const ta = document.createElement('textarea');
  document.body.append(ta);
  if (type === 'paste') {
    ta.focus();
    document.execCommand('paste');
    sendResponse(ta.value);
  } else {
    ta.value = text;
    ta.select();
    document.execCommand('copy');
    sendResponse();
  }
  ta.remove();
});
