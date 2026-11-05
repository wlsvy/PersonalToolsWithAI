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
  cmd = { "Folo", "FoloUnread" }, opts = {} }
```

전역 설치 없이 쓰려면 `opts = { cmd = { "npx", "--yes", "folocli@0.0.5" } }`로 지정합니다. 이 방식은 실행할 때마다 더 느릴 수 있습니다.

## 사용

명령은 `:Folo`, `:FoloUnread`입니다.

| 키 | 동작 |
|---|---|
| `<CR>` | 글을 열고 읽음으로 표시합니다. |
| `m` | 읽음과 안 읽음을 전환합니다. |
| `gx` | 원문을 브라우저로 엽니다. |
| `]p` | 다음 페이지를 불러옵니다. |
| `r` | 목록을 새로 불러옵니다. |
| `q` | 버퍼를 닫습니다. |

본문 변환에는 pandoc을 쓰고, 없으면 태그만 제거합니다.

## 개발

```sh
nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/cli_test.lua
```
