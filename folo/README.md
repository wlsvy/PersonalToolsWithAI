# Folo nvim 플러그인

[Folo CLI](https://github.com/RSSNext/Folo)를 감싸 Neovim에서 타임라인을 읽고 읽음 상태를 바꿉니다. 설계는 [docs/nvim.md](docs/nvim.md)에 있습니다.

## 준비

```sh
npm install -g folocli@0.0.5
folo login
```

토큰은 CLI가 관리합니다. 플러그인은 토큰을 저장하지 않습니다. 환경변수 `FOLO_TOKEN`도 사용할 수 있습니다.

## 설치

```lua
-- lazy.nvim 예시
{ dir = "~/Desktop/Workspace/PersonalToolsWithAI/folo/nvim", name = "folo", main = "folo",
  cmd = { "Folo", "FoloUnread", "FoloCategory", "FoloStarred" }, opts = {} }
```

전역 설치 없이 쓰려면 `opts = { cmd = { "npx", "--yes", "folocli@0.0.5" } }`로 지정합니다. 이 방식은 실행할 때마다 더 느릴 수 있습니다.

## 사용

| 명령 | 동작 |
|---|---|
| `:Folo` | 전체 타임라인을 엽니다. |
| `:FoloUnread` | 안 읽은 글을 엽니다. |
| `:FoloCategory` | 내 카테고리 목록에서 골라 엽니다. |
| `:FoloCategory <이름>` | 해당 카테고리를 바로 엽니다. |
| `:FoloStarred` | 컬렉션에 저장한 글을 엽니다. |

모든 명령은 왼쪽에 글 목록, 오른쪽에 미리보기를 엽니다. 커서를 옮기면 미리보기가 바뀌며, 이때는 읽음 처리하지 않습니다.

본문이 짧은 글은 Folo 추출, curl 순서로 원문을 가져와 피드 본문 아래에 덧붙입니다. curl로 읽지 못하는 페이지는 미리보기에서 `R`을 눌러 헤드리스 Chrome으로 렌더링합니다. Chrome은 매번 빈 프로필로 실행합니다. 자동 curl을 끄려면 `opts = { article = { auto_fetch = false } }`로 설정합니다.

### 목록 화면

| 키 | 동작 |
|---|---|
| `<CR>` | 읽음으로 표시하고 미리보기로 이동합니다. |
| `<Tab>` | 글을 선택하거나 해제하고 아래로 이동합니다. 선택한 글은 맨 앞에 `+`로 표시합니다. |
| `m` | 읽음과 안 읽음을 전환합니다. |
| `gx` | 선택한 글을 모두 브라우저로 엽니다. 선택이 없으면 현재 글을 엽니다. 10개를 넘으면 먼저 확인합니다. |
| `]p` | 다음 페이지를 불러옵니다. |
| `r` | 목록을 새로 불러옵니다. |
| `q` | 목록과 미리보기를 닫습니다. |

### 미리보기 화면

| 키 | 동작 |
|---|---|
| `gx` | 원문을 브라우저로 엽니다. |
| `R` | 헤드리스 Chrome으로 렌더링한 원문을 표시합니다. |
| `q` | 목록으로 돌아갑니다. |

본문 변환에는 pandoc을 쓰고, 없으면 태그만 제거합니다.

## 개발

```sh
nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/cli_test.lua
nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/article_test.lua
```
