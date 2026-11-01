# 본문 Markdown 복사 — 구현 (AI용)

사람용 문서: [clip-markdown.md](clip-markdown.md)

## 파일

| 파일 | 역할 |
|---|---|
| `mytools/features/clip-markdown/clip-markdown.js` | `export async function clipMarkdown(tabId)` → Markdown 문자열, 못 찾으면 `''` |
| `mytools/features/clip-markdown/extract.js` | 페이지에 주입되는 `extractMarkdown()` |
| `mytools/features/clip-markdown/vendor/Readability.js` | Mozilla Readability (본문 판별) |
| `mytools/features/clip-markdown/vendor/turndown.js` | HTML → Markdown |
| `mytools/popup/popup.js` | `#clip` 버튼 → `navigator.clipboard.writeText` |
| `mytools/background.js` | `MENUS.clip` → `copyText()` (offscreen 경유) |
| `mytools/offscreen/offscreen.{html,js}` | `{ type: 'copy', text }` 메시지 → `execCommand('copy')` |

## 추출 흐름

1. `clipMarkdown(tabId)`: `target = { tabId, allFrames: true }`
   - `executeScript({ files: [Readability, turndown, extract] })`로 세 파일을 모든 프레임에 주입.
   - `executeScript({ func: () => extractMarkdown() })` → 프레임별 결과 중 **가장 긴 것**을 반환.
   - allFrames 이유: 네이버 블로그처럼 본문이 iframe 안에 있는 페이지.
2. `extractMarkdown()` (페이지 컨텍스트)
   - `document.cloneNode(true)` — Readability가 넘겨받은 DOM을 직접 고치므로 복제본에서.
   - lazy-load 이미지: `data-src` / `data-lazy-src` / `data-original`을 `src`로.
   - 광고 제거는 좁게: `iframe, ins.adsbygoogle, [id^="google_ads"], [id^="div-gpt-ad"], [class*="sponsor"], [class*="advert"]`. `[class*="ad"]`처럼 넓히면 header/shadow까지 지워진다.
   - `new Readability(doc).parse()` → null이면 `''`.
   - `TurndownService({ headingStyle: 'atx', codeBlockStyle: 'fenced' })` → `# ${title}\n\n${markdown}`.
   - 재주입돼도 재선언 에러가 없도록 `extract.js` 최상위에는 function 선언만 둔다.

## 복사 경로

- popup: popup이 포커스를 가진 문서라 `navigator.clipboard.writeText` 직접. 실패/빈 결과는 `#status`에 안내.
- 우클릭(background): service worker에는 `navigator.clipboard`가 없다 → `chrome.offscreen.createDocument({ reasons: ['CLIPBOARD'] })` → `sendMessage({ type: 'copy' })` → `finally`에서 `closeDocument()`.
  - offscreen 문서는 포커스가 없어 `navigator.clipboard` 대신 textarea + `execCommand('copy')`.
  - 빈 결과면 복사하지 않음 (기존 클립보드 보존). 주입 실패는 알릴 UI가 없어 `.catch(() => {})`.

## 주의

- turndown은 링크 title을 `[text](url "title")`로 남긴다. 논문 참고문헌에서 크게 부푼다. 복사 기능은 그대로 두고, 요약 기능에서만 `stripLinkTitles()`로 지운다 ([summarize.ai.md](summarize.ai.md)).
- vendor 파일은 수정하지 않는다. 버전을 올릴 땐 파일을 통째로 교체.
- PDF 뷰어는 확장 페이지라 주입 불가.

## 테스트

자동 테스트 없음 (페이지 DOM 필요). 확인: 일반 블로그, 네이버 블로그(iframe), 논문(Nature 등), 빈 페이지에서 popup 안내 문구.
