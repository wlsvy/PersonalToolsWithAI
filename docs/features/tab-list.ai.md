# 열린 탭 목록 — 구현 (AI용)

사람용 문서: [tab-list.md](tab-list.md)

## 파일

| 파일 | 역할 |
|---|---|
| `mytools/features/tab-list/tab-list.js` | `export async function listTabs()` → `[{ id, title, url }]` |
| `mytools/popup/popup.js` | popup 로드 시(top-level await) 목록 렌더링 + 탭별 [요약] 버튼 |
| `mytools/popup/popup.html` | `#tabs` 목록과 `li` 스타일 |

## 구현

- `chrome.tabs.query({ currentWindow: true })` 결과에서 `id, title, url`만 꺼낸다.
- 다른 탭의 `title`/`url`을 읽으려면 `tabs` 권한 필요 (설치 시 "방문 기록 읽기" 경고).
- 렌더링: `li > div.text(div.title, div.url) + button`. 제목·URL은 외부 데이터라 `textContent`로만.
- [요약] 버튼
  - `!/^https?:/.test(tab.url)`이면 `disabled` (chrome://, file:// 등 주입 불가).
  - 클릭 → `openSummary(tab)` ([summarize.ai.md](summarize.ai.md)). 새 탭이 열리면서 popup이 닫힌다.
  - 실패 메시지: "본문을 찾지 못했습니다." 그대로, 그 외(주입 실패·메모리 절약으로 언로드된 탭)는 "탭을 한 번 열어 로드한 뒤 다시 시도" 안내.
  - 활성 탭이 아니므로 `activeTab`이 안 통한다 → `host_permissions: <all_urls>` 필요.

## 확장 시

- 이동/닫기: `chrome.tabs.update(id, { active: true })` / `chrome.tabs.remove(id)`.
- 모든 창: `currentWindow` 조건 제거 + `windowId`로 그룹.

## 테스트

자동 테스트 없음. 확인: popup 목록, chrome:// 탭의 버튼 비활성, 언로드된 탭 클릭 시 안내 문구.
