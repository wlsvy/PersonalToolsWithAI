# PersonalToolsWithAI — 개요

개인용 웹 유틸리티를 모은 Chrome 확장(Manifest V3, Vanilla JS)과, 확장이 할 수 없는 일(로컬 프로그램 실행, 임의 경로 파일 쓰기)을 맡는 로컬 호스트로 이루어진다.

- 빌드 없음, npm 의존성 없음. 외부 라이브러리는 파일 하나씩 `vendor/`에 복사해 둔다 (MV3는 원격 스크립트를 못 불러온다).
- 개인용. 웹 스토어 배포는 고려하지 않는다.

## 아키텍처

```
                 ┌──────────────── Chrome 확장 (mytools/) ────────────────┐
 사용자 ──클릭──▶ │ popup          버튼 · 열린 탭 목록                       │
        ──우클릭▶│ background     우클릭 메뉴 (service worker)              │
        ──입력──▶ │ content script 모든 페이지에 상주 (텍스트 치환)          │
                 │ result 탭      요약·번역 결과 화면                       │
                 │ offscreen      background 대신 클립보드 쓰기             │
                 │                                                        │
                 │ features/*     기능 로직. 위 진입점들이 import 해서 씀     │
                 └───────────────┬────────────────────────────────────────┘
                                 │ Native Messaging (요약·번역만)
                 ┌───────────────▼──────────────┐
                 │ native-host/ (Node, 내 Mac)   │──▶ claude -p (내 Claude 구독)
                 └──────────────────────────────┘
```

진입점은 화면이고, 기능은 `features/<이름>/`에 있다. 같은 기능을 popup과 우클릭 메뉴가 함께 쓴다 (예: 흑백 전환, 요약).

## 기능 목록

| 기능 | 한 줄 설명 | 사람용 | AI용 |
|---|---|---|---|
| 흑백 필터 | 현재 탭을 흑백 ↔ 원래대로 | [grayscale.md](features/grayscale.md) | [grayscale.ai.md](features/grayscale.ai.md) |
| 열린 탭 목록 | popup에 현재 창의 탭 목록 | [tab-list.md](features/tab-list.md) | [tab-list.ai.md](features/tab-list.ai.md) |
| 텍스트 치환 | 키워드 입력 → 정해둔 텍스트로 | [text-expander.md](features/text-expander.md) | [text-expander.ai.md](features/text-expander.ai.md) |
| 본문 Markdown 복사 | 페이지 본문만 Markdown으로 복사 | [clip-markdown.md](features/clip-markdown.md) | [clip-markdown.ai.md](features/clip-markdown.ai.md) |
| 요약·번역 | 글 요약 → 원하면 전문 번역 | [summarize.md](features/summarize.md) | [summarize.ai.md](features/summarize.ai.md) |

## 폴더 구조

```
mytools/                    # chrome://extensions 에서 이 폴더를 로드
├── manifest.json
├── background.js           # 우클릭 메뉴
├── offscreen/              # 클립보드 쓰기용 숨은 문서
├── popup/                  # 툴바 아이콘 popup
├── result/                 # 요약·번역 결과 탭 (+ vendor/: marked, mermaid)
├── shared/theme.css        # 확장 UI 공통 색상 토큰
└── features/
    ├── grayscale/
    ├── tab-list/
    ├── text-expander/      # content script
    ├── clip-markdown/      # (+ vendor/: Readability, turndown)
    └── summarize/

native-host/                # 확장 밖. Chrome이 실행하는 로컬 Node 스크립트
docs/
├── overview.md             # 이 문서
└── features/               # 기능별 문서 (사람용 <이름>.md, AI용 <이름>.ai.md)
```

## 권한

| 권한 | 쓰는 기능 | 이유 |
|---|---|---|
| `activeTab`, `scripting` | 흑백, 본문 복사 | 현재 탭에 스크립트 주입 |
| `host_permissions: <all_urls>` | 요약 (popup 탭 목록) | 활성 탭이 아닌 탭에 주입 |
| `tabs` | 탭 목록, 요약 | 다른 탭의 제목·URL 읽기 |
| `content_scripts: <all_urls>` | 텍스트 치환 | 모든 페이지 입력 감지 |
| `clipboardRead`, `clipboardWrite`, `offscreen` | 텍스트 치환, 본문 복사 | 클립보드 읽기·쓰기 |
| `contextMenus` | 흑백, 본문 복사, 요약 | 우클릭 메뉴 |
| `storage` | 요약 | 결과 탭에 본문 넘기기 (`storage.session`, 메모리 전용) |
| `nativeMessaging` | 요약 | 로컬 호스트 호출 |
| `sidePanel` | 요약 (사이드 패널) | 현재 탭 옆에 결과 페이지 표시 |

설치 시 "모든 웹사이트의 데이터 읽기 및 변경", "방문 기록 읽기" 경고가 뜬다. 입력·본문은 요약 기능을 쓸 때만 로컬 호스트 → Claude로 나가고, 그 외에는 어디에도 보내지 않는다.

## 설치

1. `chrome://extensions` → 개발자 모드 → "압축해제된 확장 프로그램 로드" → `mytools/`
2. 요약 기능을 쓸 때만: [summarize.md](features/summarize.md)의 설치 절차 (호스트 등록 + 로그인)

코드 수정 후에는 `chrome://extensions`에서 새로고침. content script(텍스트 치환)는 열려 있던 탭도 새로고침해야 반영된다.

## 공통 규칙

- 기능 로직은 `features/<이름>/`에 두고 함수를 export 한다. popup·background·result가 import 해서 연결만 한다.
- 확장 페이지에 inline script 금지 (CSP). `<script type="module" src="...">`로만.
- content script는 ES Module을 못 쓴다 → 일반 스크립트로, manifest 순서대로 로드되어 전역을 공유.
- 페이지 제목·본문 같은 외부 데이터는 `textContent`로 넣는다. HTML로 렌더링할 땐 raw HTML을 이스케이프한다.
- 알고 쓰는 한계는 코드에 `// shortcut: <한계>, <언제 고칠지>` 주석으로 남긴다.
- 테스트는 `node <파일>.test.mjs` (assert 기반, 프레임워크 없음).

## 기능 추가 방법

1. `mytools/features/<이름>/`에 로직 추가
2. 진입점 연결
   - popup 버튼: `popup.js`에서 import, `popup.html`에 버튼
   - 우클릭 메뉴: `background.js`의 `MENUS`에 항목 추가 (`onInstalled` 때 등록되므로 확장 새로고침 필요)
   - 페이지 상주: `manifest.json`의 `content_scripts`에 등록
3. 필요한 권한을 manifest와 이 문서의 권한 표에 추가
4. `docs/features/<이름>.md`(사람용), `<이름>.ai.md`(AI용) 작성, 위 기능 목록에 추가

## 문서 규칙

- **사람용 `<이름>.md`**: 무엇을 하는지, 어떻게 쓰는지, 한계, 나중에 할 것. API 이름·코드 없이.
- **AI용 `<이름>.ai.md`**: 파일·함수·흐름·결정 이유·주의점·테스트 방법. 코드를 고치기 전에 읽고, 고친 뒤 갱신한다.
- 기능 동작이 바뀌면 두 문서를 함께 고친다.

## 필요해지면 그때 할 것

| 신호 | 할 일 |
|---|---|
| 기능이 많아져 popup.js가 길어짐 | 기능 목록 파일(registry) 분리 |
| 웹 스토어 배포 | 아이콘 추가, zip 패키징 스크립트 |
| 다크 모드 | `shared/theme.css`에 `prefers-color-scheme: dark` 토큰 추가 |
