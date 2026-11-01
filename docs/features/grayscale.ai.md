# 흑백 필터 — 구현 (AI용)

사람용 문서: [grayscale.md](grayscale.md)

## 파일

| 파일 | 역할 |
|---|---|
| `mytools/features/grayscale/grayscale.js` | `export function toggleGrayscale(tabId)` |
| `mytools/popup/popup.js` | `#grayscale` 버튼 → 활성 탭 id로 호출, 실패 시 `#status`에 안내 |
| `mytools/background.js` | `MENUS.grayscale` 우클릭 메뉴 → `tab.id`로 호출, 실패는 무시 |

## 구현

- `chrome.scripting.executeScript({ target: { tabId }, func })`로 페이지의 `document.documentElement.style.filter`를 `'grayscale(1)'` ↔ `''` 토글.
- 상태는 페이지 DOM에만 있다. storage·background 상태 없음.
- 권한: `activeTab` + `scripting`. popup을 열거나 우클릭한 순간 현재 탭 권한이 생기므로 충분.

## 결정·주의

- `insertCSS` 대신 inline style: 토글 판단을 style 값 하나로 할 수 있어 코드가 가장 짧다.
  - shortcut 주석 있음: 페이지가 `<html>`에 inline `filter`를 직접 쓰면 덮어쓴다. 문제되면 `insertCSS` + 전용 class로 바꾼다.
- `<html>`에 `filter`가 걸리면 그 요소가 `position: fixed` 자식의 containing block이 되어 고정 요소 위치가 틀어질 수 있다 (CSS 사양상 동작).
- `chrome://`, 웹 스토어는 주입 불가 → `executeScript`가 reject. popup은 안내 문구, background는 `.catch(() => {})`.

## 확장 시

- 상태 유지가 필요해지면: `storage` + `chrome.scripting.registerContentScripts`(등록형 content script)로 페이지 로드 시 재적용.

## 테스트

자동 테스트 없음 (Chrome API 호출 한 줄). 확인: 일반 페이지에서 토글 2회, `chrome://extensions`에서 popup 안내 문구.
