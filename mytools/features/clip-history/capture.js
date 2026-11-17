// 페이지에서 복사·잘라내기한 텍스트를 background에 넘겨 히스토리에 남긴다.
// content script는 storage.session에 접근할 수 없어 메시지로 넘긴다.
// 페이지가 navigator.clipboard.writeText로 직접 쓰는 복사 버튼(GitHub 등)은 이벤트가 없어 잡지 못한다.
for (const type of ['copy', 'cut']) {
  document.addEventListener(type, () => {
    const text = copiedText(document.activeElement);
    // 확장을 새로고침한 뒤 남아 있던 탭에서는 실패하므로 무시한다
    if (text) chrome.runtime.sendMessage({ type: 'clip-history', text }).catch(() => {});
  }, true);
}

// 입력창 선택은 getSelection()에 잡히지 않아 따로 읽는다
function copiedText(el) {
  if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
    if (el.type === 'password' || typeof el.selectionEnd !== 'number') return '';
    return el.value.slice(el.selectionStart, el.selectionEnd);
  }
  return getSelection().toString();
}
