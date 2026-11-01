# 텍스트 치환 — 구현 (AI용)

사람용 문서: [text-expander.md](text-expander.md)

## 파일

| 파일 | 역할 |
|---|---|
| `mytools/features/text-expander/snippets.js` | 전역 `SNIPPETS` (키워드 → 텍스트를 돌려주는 함수, Promise 가능), `today()`, `clipboardText()` |
| `mytools/features/text-expander/expander.js` | 입력 감지 + 치환 |
| `mytools/manifest.json` | `content_scripts: <all_urls>`에 snippets.js → expander.js 순서로 등록 |

content script는 ES Module을 못 쓴다. 두 파일은 일반 스크립트이고 manifest 순서대로 로드되어 전역 스코프를 공유한다 (`expander.js`가 `SNIPPETS`를 전역으로 참조).

## 스니펫 정의

```js
const SNIPPETS = {
  '//copy': () => `회의 메모 ${today()} ${clipboardText()}`,
  '//date': () => today(),
};
```

함수라서 템플릿 문법 파서가 필요 없다.
- `today()`: `toLocaleDateString('sv-SE')` → 로컬 시간대 YYYY-MM-DD.
- `clipboardText()`: 화면 밖 임시 textarea에 포커스 → `document.execCommand('paste')` → 값 읽고 제거. `clipboardRead` 권한이 있어 content script에서 동작. 포커스가 잠시 옮겨진다.

## 치환 흐름 (`expander.js`)

1. `document`에 capture 단계 리스너: `input`(`e.isComposing`이면 무시), `compositionend`.
   - 한글 IME 조합 중에는 검사하지 않고 조합이 끝난 뒤 판단.
2. `caret(el)` → `{ before, select(n) }` 또는 `null`
   - `<input>`/`<textarea>`: `selectionEnd` 기준. `type=password` 제외, `selectionEnd`가 number가 아닌 타입(email, number 등) 제외.
   - `contenteditable`: `getSelection()`의 anchor가 텍스트 노드이고 collapsed일 때만.
     - shortcut 주석 있음: 키워드가 텍스트 노드 하나 안에 있을 때만 인식. 서식 때문에 노드가 쪼개지는 경우가 문제되면 Range로 거슬러 탐색.
3. `before`가 끝나는 키워드를 `SNIPPETS`에서 찾음 (객체 순서상 첫 일치 → 앞부분이 겹치면 짧은 쪽이 먼저 걸림).
4. `busy = true` → 스니펫 실행(`await`) → `el.focus()` 복원 → `select(key.length)`가 true면 `document.execCommand('insertText', false, text)`.
   - `select()`는 스니펫 실행 중 내용이 바뀌었으면 false (키워드가 그대로일 때만 치환).
   - `busy`: 치환 중 생기는 `input` 이벤트(붙여넣기, insertText) 재진입 방지.

## 결정·주의

- `execCommand('insertText')`: deprecated지만 input/textarea/contenteditable을 한 방법으로 처리하고, 페이지의 `input` 이벤트가 정상 발생하며 Undo 스택에 남는다. 대체 API가 아직 없다.
- iframe: content script가 `all_frames` 없이 등록돼 top frame만. Google Docs는 canvas 기반이라 불가.
- 클립보드 읽기가 사이트별로 프롬프트 없이 되는지는 전부 확인하지 않았다. 안 되는 사이트가 나오면 offscreen 문서에서 읽어 메시지로 받는 방식으로 바꾼다 (본문 복사의 offscreen 패턴 참고).

## 확장 시

- 편집 UI: `storage.sync`에 스니펫 저장 + options 페이지 + `{date}`/`{clipboard}` 템플릿 파서.
- 날짜 형식: `today(format)` 인자 추가.

## 테스트

자동 테스트 없음. 확인: textarea / input / contenteditable(Gmail 등)에서 `//date`, `//copy`, 한글 입력 직후 키워드, Undo, 비밀번호 칸 제외.
