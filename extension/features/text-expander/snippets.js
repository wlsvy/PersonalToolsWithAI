// 텍스트 치환 스니펫: 키워드 → 넣을 텍스트를 돌려주는 함수 (Promise도 가능)
// 수정 후 chrome://extensions 에서 확장 새로고침 + 열려 있던 탭도 새로고침해야 반영된다.
// 키워드끼리 앞부분이 겹치면(//c, //copy) 짧은 쪽만 동작한다.
const SNIPPETS = {
  '//copy': () => `회의 메모 ${today()} ${clipboardText()}`,
  '//date': () => today(),
};

// 오늘 날짜 YYYY-MM-DD (로컬 시간대). sv-SE 로케일이 이 형식이다.
function today() {
  return new Date().toLocaleDateString('sv-SE');
}

// 클립보드 텍스트. clipboardRead 권한으로 임시 textarea에 붙여넣어 읽는다 (포커스가 잠시 옮겨짐).
function clipboardText() {
  const ta = document.createElement('textarea');
  ta.style.cssText = 'position:fixed;top:0;left:0;opacity:0';
  document.documentElement.append(ta);
  ta.focus({ preventScroll: true });
  document.execCommand('paste');
  const text = ta.value;
  ta.remove();
  return text;
}
