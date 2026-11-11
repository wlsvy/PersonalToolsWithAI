# 글 요약·번역 — 구현 (AI용)

사람용 문서: [summarize.md](summarize.md)

## 파일

| 파일 | 역할 |
|---|---|
| `mytools/features/summarize/summarize.js` | `openSummary(tab)`, `openSummaryPanel(tab)`, `fillSummary(key, tab)`, `countWords(text)`, `stripLinkTitles(md)`, `stripCitations(md)`, `sourceLink(title, url)` |
| `mytools/features/summarize/summarize.test.mjs` | 위 순수 함수 테스트 (`node`로 실행) |
| `mytools/background.js` | `MENUS.summary` → `openSummary(tab)`, `MENUS['summary-panel']` → `openSummaryPanel` + `fillSummary`, `onMessage('summary-panel')` → `fillSummary` |
| `mytools/popup/popup.js` | [사이드 패널에 요약] → `openSummaryPanel(activeTab)` + `sendMessage({ type: 'summary-panel', key, tab })` 후 `window.close()` |
| `mytools/popup/popup.js` | 탭 목록의 [요약] 버튼 → `openSummary(tab, { active: false })` (뒤에서 열기, popup 유지) ([tab-list.ai.md](tab-list.ai.md)) |
| `mytools/result/result.{html,js}` | 결과 탭: 요약 요청·표시, [요약 Markdown 복사], [마저 번역], [번역 Markdown 복사] |
| `mytools/result/vendor/marked.esm.js` | marked 18.1.1 (ESM) |
| `mytools/result/vendor/mermaid.min.js` | mermaid 12.2.0 (UMD, `globalThis.mermaid`, 5.5MB) |
| `native-host/clip_host.mjs` | Native Messaging 호스트: `claude -p` 호출 |
| `native-host/prompts/summary.md`, `translate.md` | 시스템 프롬프트 |
| `native-host/install.sh` | 호스트 등록 JSON + node wrapper 생성 |

`native-host/prompts/*.md`는 Folo Neovim 플러그인도 함께 씁니다([folo/docs/ai.ai.md](../../folo/docs/ai.ai.md)). 호출 인자를 바꾸면 양쪽을 맞춰야 합니다.

## 흐름

```
[우클릭 / popup [요약]]
  openSummary(tab)                         (background 또는 popup 컨텍스트)
    clipMarkdown(tab.id) → stripLinkTitles → stripCitations → countWords
    storage.session[uuid] = { title, url, markdown, words }
    tabs.create(result/result.html?id=uuid)
[result.js]
  storage.session[id] 읽기 (없으면 안내)
  doc.summary 없으면 → sendNativeMessage({ action: 'summary', markdown })
                      → 성공 시 doc.summary 저장 (새로고침해도 재요약 안 함)
  render(#summary, sourceLink(title, url) + doc.summary)   (링크는 저장하지 않고 표시·복사 때 붙임)
  [요약 Markdown 복사] → navigator.clipboard.writeText(링크 + doc.summary)
  [마저 번역] → sendNativeMessage({ action: 'translate', markdown }) → doc.translation 저장 → render(#translation)
  [번역 Markdown 복사] → navigator.clipboard.writeText(doc.translation)   (번역이 있을 때만 보임)
[clip_host.mjs]
  summary: ask('sonnet', 'summary.md', markdown) → { ok, text }
  translate: ask('sonnet', 'translate.md', markdown) → { ok, text }
  실패:    { ok: false, error }
```

## 사이드 패널

- `sidePanel.open()`은 사용자 제스처 안에서만 동작합니다. 클릭 뒤 `await`(추출, `tabs.query`)를 거치면 제스처가 끊기므로 `setOptions({ tabId, path: result.html?id=key })`와 `open({ tabId })`를 동기로 먼저 부르고, 추출은 그 뒤에 합니다. popup은 활성 탭을 로드 시점에 미리 조회해 둡니다.
- 패널이 열리면 popup이 닫히므로 popup은 추출을 background에 메시지로 넘깁니다. 우클릭 메뉴는 이미 background라 `fillSummary`를 직접 부릅니다.
- `result.js` `loadDoc()`: `storage.onChanged` 리스너를 먼저 달고 `get` → 없으면 "본문 추출 중…" 표시 후 최대 15초 대기합니다. 추출 실패는 `fillSummary`가 `{ error }`를 같은 키에 넣어 알립니다.
- manifest에 `side_panel.default_path`를 두지 않습니다. 패널은 `setOptions`로 연 탭에만 붙습니다.
- 미확인: 실제 Chrome에서 popup 클릭 → 패널 열림, 우클릭 메뉴 → 패널 열림을 아직 확인하지 않았습니다.

## 확장 측 결정

- **결과 탭은 원래 탭에 의존하지 않는다.** 추출은 클릭 순간(사용자 제스처로 권한이 있는 시점)에 끝내고, 결과 탭은 session 데이터만 읽는다.
- `storage.session`으로 넘기는 이유: URL 쿼리는 본문(수십 KB)을 싣기에 길고, `sendMessage`는 탭 로딩 전에 도착하는 경쟁 상태가 있다. session은 메모리 전용이라 브라우저 종료 시 사라진다.
  - 탭을 그냥 닫으면 키가 남는다. 브라우저 종료 시 사라지므로 정리 코드 없음. 쌓여서 문제되면 `tabs.onRemoved`로 정리.
- 요청 주체를 결과 탭으로 둔 이유: popup은 포커스를 잃으면 닫히고, service worker는 유휴 시 종료될 수 있다. 열린 탭은 수 분짜리 번역 동안에도 살아 있다.
- `sendNativeMessage`(일회성)를 쓴다. 호스트는 메시지마다 실행되고 응답 후 종료. 실패(호스트 미등록 등)는 `ask()`가 `{ ok: false, error }`로 바꾸고, `not found`면 install.sh 안내를 붙인다.
- popup [요약]은 활성 탭이 아닌 탭에 주입 → `host_permissions: <all_urls>` 필요.
- `stripLinkTitles`: turndown이 URL의 괄호와 title의 따옴표를 `\`로 이스케이프하는 것을 고려한 정규식. `[1](url "저자…")` → `[1](url)`.
- `stripCitations`: 텍스트가 숫자(또는 `\[n\]`, `n–m`)뿐인 링크와 그 사이 쉼표·대시를 묶음째 삭제합니다. 요약·번역 입력과 "원문 Markdown" 표시 모두에서 빠집니다.
- `countWords`: `split(/\s+/)` 기준. Markdown 문법·URL도 단어로 센다 (대략치).

## 렌더링 (`result.js`의 `render`)

- `marked.parse()` → `innerHTML`. LLM 출력은 웹 글에서 온 신뢰할 수 없는 입력이므로 `renderer.html`을 이스케이프로 덮어써 raw HTML을 글자로 표시. 스크립트·`javascript:` 링크는 확장 CSP(`script-src 'self'`)가 막는다.
- `pre > code.language-mermaid`가 있을 때만 `vendor/mermaid.min.js`를 `<script>`로 동적 로드 → `initialize({ startOnLoad: false, securityLevel: 'strict' })` → 블록을 `div.mermaid`로 교체 → `mermaid.run({ suppressErrors: true })`.
- `<base target="_blank">`: 본문 링크가 결과 탭을 떠나지 않게.
- 원문 Markdown(`#source`)은 렌더링 없이 `textContent`.
- vendor 버전을 올릴 땐 2주 이상 지난 릴리스로, 파일 통째로 교체. mermaid는 `eval`/`new Function`을 쓰지 않는지 확인 (CSP).

## 호스트 측 결정 (`clip_host.mjs`)

- 호출: `claude -p --model <m> --system-prompt <prompts/*.md 내용> --tools '' --no-session-persistence`, 본문은 stdin.
  - `spawnSync`의 `input` + `encoding: 'utf8'` (조각 단위로 이어 붙이면 멀티바이트가 깨질 수 있음), `maxBuffer` 16MB.
- `CLAUDE_CONFIG_DIR=~/.claude-clip`: 전역 `~/.claude`의 CLAUDE.md·플러그인·hook이 출력에 섞이지 않게 별도 프로필. 최초 1회 로그인 필요.
- `cwd: tmpdir()`: 이 저장소의 CLAUDE.md/.claude가 읽히지 않게.
- `--tools ''`: 입력이 신뢰할 수 없는 웹 본문 → 프롬프트 인젝션 대비. 파일은 쓰지 않는다.
- `--bare` 금지: `ANTHROPIC_API_KEY`/apiKeyHelper만 쓰고 OAuth·키체인을 읽지 않아 구독 로그인이 안 된다.
- claude.ai 쿠키로 내부 API 호출은 하지 않는다 (비공개 API, 약관·계정 위험).
- `claude` 위치: `PATH` + `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`에서 탐색.
- 메시지 프로토콜: 4바이트 길이(native byte order, macOS little-endian) + UTF-8 JSON. 호스트 → Chrome 응답은 최대 1MB.
- `process.argv[1]`이 자기 자신일 때만 main 실행 → 테스트에서 import 가능.

## 설치 구조

- Dock에서 실행된 Chrome은 PATH가 `/usr/bin:/bin`뿐 → `install.sh`가 `command -v node` 절대 경로를 박은 wrapper를 만든다.
- 생성물 (저장소 밖): `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
  - `com.personaltools.clip.sh`: `exec "<node>" "<repo>/native-host/clip_host.mjs"`
  - `com.personaltools.clip.json`: `path` = wrapper, `allowed_origins` = `chrome-extension://<ID>/`
- 다시 실행해야 할 때: 확장 ID 변경(`mytools/` 경로 변경), `native-host/` 이동, node 경로 변경(nvm 등).

## 미확인

- 논문 한 편 전문 번역이 한 번의 호출 출력 한도에 들어가는지. 안 되면 `## ` 제목 단위로 나눠 호출 후 이어 붙인다.
- `CLAUDE_CONFIG_DIR`별로 키체인 로그인이 분리되는지 (기본 프로필 로그인이 유지되는지).
- marked 렌더링·mermaid는 브라우저에서만 확인 가능 (외부 코드라 node 실행 안 함).

## 테스트

- `node mytools/features/summarize/summarize.test.mjs` → `ok`
- 호스트 프로토콜: 길이 접두 JSON을 wrapper에 stdin으로 넣고 응답 확인. `PATH=/usr/bin:/bin`으로 Chrome 환경 재현. `{ action: 'nope' }` → unknown action 오류.
