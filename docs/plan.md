# PersonalToolsWithAI — 계획

Vanilla JS Chrome 확장 (Manifest V3). 빌드 없음, 의존성 없음, 저장소(storage) 없음.

툴바 아이콘 클릭 → popup이 열리고, popup에서 각 기능을 사용한다.
(텍스트 치환은 popup 없이 웹 페이지 입력창에서 동작)

## 기능

### 1. 흑백 필터
popup의 버튼 클릭 → **현재 탭**이 흑백 ↔ 원래대로 토글.

- 상태를 저장하지 않는다. 페이지 이동/새로고침 시 원래대로 돌아온다.
- `chrome.scripting.executeScript`로 페이지의 `<html>`에 `filter: grayscale(1)`을 넣고 빼는 것 하나.

### 2. 열린 탭 목록
popup을 열면 현재 창에 열린 탭들의 **제목과 URL**을 목록으로 보여준다.

- `chrome.tabs.query({ currentWindow: true })` 결과를 그대로 렌더링.
- 표시만 한다. 클릭 동작 없음.

### 3. 텍스트 치환 (Text Blaze 축소판)
웹 페이지 입력창에 키워드를 입력하는 순간 정해둔 텍스트로 바뀐다.

예: `//copy` 입력 → `회의 메모 2026-11-01 <클립보드 내용>`

**스니펫은 코드에 직접 정의한다** (storage·편집 UI 없음). 각 스니펫은 문자열을 돌려주는 함수라서 템플릿 문법 파서가 필요 없다.

```js
// features/text-expander/snippets.js
const SNIPPETS = {
  '//copy': () => `회의 메모 ${today()} ${clipboardText()}`,
  '//date': () => today(),
};
```

동작 순서:
1. `input` 이벤트마다 커서 앞 텍스트가 등록된 키워드로 끝나는지 확인
2. 일치하면 키워드 범위를 선택 → `document.execCommand('insertText', false, 결과)`로 교체
   - `<input>`, `<textarea>`, `contenteditable`(Gmail, Notion 등) 모두 한 가지 방법으로 처리
   - 페이지의 `input` 이벤트가 정상 발생하고 Ctrl+Z 되돌리기도 동작
   - `execCommand`는 deprecated지만 이 용도의 대체 API가 아직 없음

Text Blaze 대비 범위:

| Text Blaze | 이번 계획 |
|---|---|
| `{time: 형식}` 날짜/시간 | ✅ `today()` (YYYY-MM-DD 고정) |
| `{clipboard}` | ✅ `clipboardText()` |
| `{cursor}` 커서 위치 지정 | ❌ 결과 끝에 커서 |
| `{formtext}` 등 입력 폼 | ❌ |
| `{site}`, `{if}`, `{=}` 수식 | ❌ |
| 스니펫 편집 UI · 동기화 | ❌ 코드 수정 후 확장 새로고침 |
| 우클릭 메뉴 · 단축키 검색창 | ❌ |

## 구조

```
extension/                  # chrome://extensions 에서 이 폴더를 로드
├── manifest.json
├── popup/
│   ├── popup.html
│   └── popup.js            # 흑백·탭 목록 기능을 import 해서 연결
└── features/
    ├── grayscale/
    │   └── grayscale.js    # export function toggleGrayscale(tabId)
    ├── tab-list/
    │   └── tab-list.js     # export function listTabs() → [{ title, url }]
    └── text-expander/      # content script (모든 페이지에 주입)
        ├── snippets.js     # 키워드 → 텍스트 함수 정의
        └── expander.js     # 입력 감지 + 치환
```

```json
{
  "manifest_version": 3,
  "name": "PersonalToolsWithAI",
  "version": "0.1.0",
  "permissions": ["activeTab", "scripting", "tabs", "clipboardRead"],
  "action": { "default_popup": "popup/popup.html", "default_title": "PersonalToolsWithAI" },
  "content_scripts": [{
    "matches": ["<all_urls>"],
    "js": ["features/text-expander/snippets.js", "features/text-expander/expander.js"]
  }]
}
```

- background(service worker) 없음. popup 안에서 Chrome API를 직접 호출한다.
- `activeTab`: popup을 여는 순간 현재 탭 접근 권한이 생기므로 흑백 필터에 충분.
- `tabs`: 다른 탭의 제목/URL 읽기. 설치 시 "방문 기록 읽기" 경고.
- `content_scripts` + `<all_urls>`: 텍스트 치환이 모든 페이지 입력을 감지해야 하므로 필요. 설치 시 "모든 웹사이트의 데이터 읽기 및 변경" 경고. 입력 내용은 로컬에서 키워드 비교만 하고 어디에도 보내지 않는다.
- `clipboardRead`: 클립보드 읽기.
- content script는 ES Module을 쓸 수 없다 → `snippets.js`, `expander.js`는 일반 스크립트로, manifest에 적은 순서대로 로드되어 전역 스코프를 공유한다.
- popup 스크립트는 `<script type="module" src="popup.js">` (inline script 금지, CSP).

## 구현 전 확인 (스파이크)

- **content script에서 클립보드 읽기**: `navigator.clipboard.readText()`는 웹 페이지 권한 기준이라 사이트마다 허용 팝업이 뜰 수 있다. `clipboardRead` 권한 + `document.execCommand('paste')` 방식이 content script에서 프롬프트 없이 되는지 먼저 확인한다. 안 되면 offscreen document를 통해 읽는 방식으로 간다 (background 추가 필요).

## 기능 추가 방법

- popup 기능: `features/<이름>/`에 파일 추가 → `popup.js`에서 import, `popup.html`에 버튼/영역 추가
- 페이지 상주 기능: `features/<이름>/`에 파일 추가 → `manifest.json`의 `content_scripts`에 등록

## 필요해지면 그때 할 것

| 신호 | 할 일 |
|---|---|
| 새로고침/새 탭에도 흑백 유지를 원함 | `storage` + background + 등록형 content script 도입 |
| 탭 목록에서 클릭하여 이동/닫기를 원함 | `chrome.tabs.update` / `chrome.tabs.remove` 연결 |
| 모든 창의 탭을 보고 싶음 | `currentWindow` 조건 제거, 창별 그룹 표시 |
| 스니펫을 코드 수정 없이 편집하고 싶음 | `storage` + 편집 UI + `{date}` 같은 템플릿 문법 파서 |
| 날짜 형식을 바꾸고 싶음 | `today()`에 형식 인자 추가 |
| 기능이 많아져 popup.js가 길어짐 | 기능 목록 파일(registry) 분리 |
| 웹 스토어 배포 | 아이콘 추가, zip 패키징 스크립트 |

## 알려진 한계

- 흑백 필터는 `chrome://` 페이지, Chrome 웹 스토어에서 동작하지 않음 (Chrome 정책).
- `<html>`에 `filter`를 걸면 일부 사이트에서 `position: fixed` 요소 위치가 틀어질 수 있음.
- 텍스트 치환
  - 키워드가 입력되는 즉시 바뀌므로, 한 키워드가 다른 키워드의 앞부분이면(`//c`와 `//copy`) 짧은 쪽만 동작한다 → 키워드끼리 앞부분이 겹치지 않게 정한다.
  - 비밀번호 입력창은 제외한다.
  - iframe 안의 입력창, Google Docs(canvas 기반 편집기)에서는 동작하지 않는다.
  - 한글 입력 조합 중(IME composition)에는 검사하지 않는다 — `compositionend` 이후 판단.
