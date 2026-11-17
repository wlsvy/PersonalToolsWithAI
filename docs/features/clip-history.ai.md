# 클립보드 기록 — 구현 (AI용)

사람용 문서: [clip-history.md](clip-history.md)

## 파일

| 파일 | 역할 |
|---|---|
| `mytools/features/clip-history/clip-history.js` | `recentClips()`, `rememberClip(text)`, 순수 함수 `pushClip(list, text)`입니다 |
| `mytools/features/clip-history/capture.js` | content script입니다. 페이지의 `copy`/`cut` 이벤트에서 선택 텍스트를 `{ type: 'clip-history', text }`로 background에 보냅니다 |
| `mytools/background.js` | `clip-history` 메시지를 받으면 `rememberClip`을 호출합니다. `copyText()`도 복사한 뒤 기록합니다 |
| `mytools/popup/popup.{html,js}` | 열 때 `readText()`로 현재 클립보드를 기록하고, `#history`에 목록을 그립니다 |
| `mytools/result/result.js` | `copy()`가 복사한 뒤 기록합니다 |

## 결정

- OS 클립보드 변경 이벤트가 없어 복사 지점마다 기록합니다. offscreen 폴링은 문서를 계속 열어 둬야 해서 쓰지 않았습니다.
- 저장소는 `chrome.storage.session`(키 `clipHistory`, 최신순 배열)입니다. 디스크에 남기지 않기 위해서입니다. 영구 보관이 필요해지면 `storage.local`로 바꾸면 되지만, 비밀번호 노출 위험을 다시 따져야 합니다.
- content script는 `storage.session`에 기본적으로 접근할 수 없어 메시지로 넘깁니다(`setAccessLevel`은 쓰지 않습니다).
- `pushClip`은 새 텍스트가 접두사로 포함하는 기존 항목(`text.startsWith(t.trimEnd())`)을 지웁니다. 동일 항목 중복 제거와 이어 붙이기 대체를 한 조건으로 처리합니다. 대신 짧은 접두사 항목이 사라지는 부작용이 있어 코드에 `shortcut:` 주석을 남겼습니다.
- 입력창의 선택 영역은 `getSelection()`에 잡히지 않아 `selectionStart/End`로 읽습니다. `type=password`는 건너뜁니다.

## 주의

- read-modify-write라 거의 동시에 두 번 기록하면 하나가 사라질 수 있습니다. 사람의 복사 속도에서는 문제가 되지 않아 직렬화하지 않았습니다.
- popup의 `readText()`는 포커스를 잃으면 실패하므로 try/catch로 무시합니다.
- 목록 텍스트는 외부 데이터이므로 `textContent`로만 넣습니다.

## 테스트

`node mytools/features/clip-history/clip-history.test.mjs`로 `pushClip`(중복, 5개 제한, 이어 붙이기 대체)을 검사합니다. 나머지는 수동으로 확인합니다. 페이지에서 Cmd+C, 입력창에서 Cmd+X, 다른 앱에서 복사한 뒤 popup 열기, [복사] 버튼으로 다시 복사하는 경우를 확인합니다.
