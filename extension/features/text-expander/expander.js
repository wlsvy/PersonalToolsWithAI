// 입력창에 SNIPPETS 키워드를 치는 순간 스니펫 결과로 바꾼다.
// content script는 모듈을 못 쓰므로 manifest에서 먼저 로드된 snippets.js의 전역 SNIPPETS를 쓴다.

let busy = false; // 치환 중에 생기는 input 이벤트(붙여넣기, insertText)는 무시

document.addEventListener('input', (e) => { if (!e.isComposing) expand(e.target); }, true);
document.addEventListener('compositionend', (e) => expand(e.target), true);

async function expand(el) {
  if (busy) return;
  const at = caret(el);
  if (!at) return;
  const key = Object.keys(SNIPPETS).find((k) => at.before.endsWith(k));
  if (!key) return;

  busy = true;
  try {
    const text = await SNIPPETS[key]();
    // 스니펫이 포커스를 옮겼을 수 있으니(클립보드 읽기) 되돌리고, 키워드가 그대로일 때만 바꾼다
    el.focus();
    if (at.select(key.length)) document.execCommand('insertText', false, text);
  } finally {
    busy = false;
  }
}

// 커서 앞 텍스트(before)와, 커서 앞 n글자를 선택하는 select(n). 대상이 아니면 null
function caret(el) {
  if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
    // email/number 등은 selectionEnd가 null
    if (el.type === 'password' || typeof el.selectionEnd !== 'number') return null;
    const end = el.selectionEnd;
    const before = el.value.slice(0, end);
    return {
      before,
      select(n) {
        if (el.value.slice(0, end) !== before) return false;
        el.setSelectionRange(end - n, end);
        return true;
      },
    };
  }
  if (el.isContentEditable) {
    const sel = getSelection();
    const node = sel.anchorNode;
    const end = sel.anchorOffset;
    // shortcut: 키워드가 텍스트 노드 하나 안에 있을 때만 인식, 서식 때문에 노드가 쪼개지는 경우가 문제되면 Range로 거슬러 탐색
    if (!sel.isCollapsed || node?.nodeType !== Node.TEXT_NODE) return null;
    const before = node.data.slice(0, end);
    return {
      before,
      select(n) {
        if (!node.isConnected || node.data.slice(0, end) !== before) return false;
        sel.setBaseAndExtent(node, end - n, node, end);
        return true;
      },
    };
  }
  return null;
}
