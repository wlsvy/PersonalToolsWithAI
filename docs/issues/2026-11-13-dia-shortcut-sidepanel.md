# Dia에서 사이드 패널 요약 단축키가 동작하지 않음

- 날짜: 2026-11-13
- 대상: `mytools` 확장, Dia 브라우저(macOS), 명령 `summary-panel`(⌥⇧J)

## 증상

⌥⇧J를 누르면 아무 반응이 없었습니다. 같은 기능을 우클릭 메뉴로 실행하면 정상 동작했습니다. 오류는 `background.js`의 `.catch(() => {})`가 삼켜서 보이지 않았습니다.

## 디버깅 과정

| 단계 | 가설 | 확인 방법 | 결과 |
|---|---|---|---|
| 1 | `suggested_key`를 바꾼 뒤 재설치하지 않아 키가 등록되지 않았습니다. | 단축키 설정 화면을 확인했습니다. | ⌥⇧J가 등록되어 있어 이 가설은 틀렸습니다. |
| 2 | Dia나 다른 앱이 ⌥⇧J를 먼저 가져갑니다. | 공개된 Dia 단축키 목록을 확인했습니다. | 충돌하는 키를 찾지 못했습니다. |
| 3 | 우클릭 메뉴는 되므로 키 입력 쪽 문제입니다. | `onCommand`에 로그를 넣고 오류를 콘솔에 출력하게 했습니다. | 이벤트는 들어왔지만 `tab`이 `undefined`였습니다(`Cannot read properties of undefined (reading 'id')`). |
| 4 | 활성 탭을 조회해 채웁니다. | `chrome.tabs.query`를 `await`한 뒤 실행했습니다. | `` `sidePanel.open()` may only be called in response to a user gesture. `` 오류가 났습니다. |
| 5 | 패널을 먼저 열고 탭은 나중에 찾습니다. | `windowId: WINDOW_ID_CURRENT`로 `sidePanel.open()`을 동기 호출했습니다. | 정상 동작했습니다. |

## 원인

1. **Dia는 `chrome.commands.onCommand`에 `tab` 인자를 넘기지 않습니다.** Chrome은 이 인자를 넘깁니다.
2. **`sidePanel.open()`은 사용자 동작(user gesture) 안에서만 호출할 수 있습니다.** 앞에서 `await`을 거치면 사용자 동작으로 인정되지 않습니다.

## 조치

- `features/summarize/summarize.js`의 `openSummaryPanel`은 `tab`이 없으면 창 전체에 패널 경로를 설정합니다. 그다음 `sidePanel.open({ windowId: chrome.windows.WINDOW_ID_CURRENT })`를 `await` 없이 호출합니다.
- `background.js`의 `summary-panel` 실행 함수는 패널을 연 뒤 활성 탭을 조회하고, 그 탭에서 본문을 추출합니다.
- `onCommand`의 오류는 삼키지 않고 `console.error`로 출력합니다.

## 남은 제약

- 우클릭 메뉴로 패널을 연 적이 있는 탭에는 그 탭 전용 경로가 남아 있습니다. 탭 전용 설정이 창 전체 설정보다 우선하므로, 그 탭에서 단축키를 누르면 이전 요약이 보일 수 있습니다. 이 현상은 아직 확인하지 않았습니다.
- 확장을 새로고침할 때 콘솔에 `Cannot find menu item with id ...` 오류가 나옵니다. `onStartup`의 메뉴 제목 갱신이 메뉴가 만들어지기 전에 실행되어 생기는 오류입니다. 메뉴 동작에는 영향이 없습니다.

## 교훈

Chromium 기반 브라우저라도 확장 API의 인자와 사용자 동작 판정이 Chrome과 다를 수 있습니다. 오류를 `.catch(() => {})`로 삼키면 이런 차이를 찾기 어렵습니다.
