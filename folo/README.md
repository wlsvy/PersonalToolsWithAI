# Folo nvim 플러그인

[Folo CLI](https://github.com/RSSNext/Folo)를 감싸 Neovim에서 타임라인을 읽고 읽음 상태를 바꿉니다. 설계는 [docs/nvim.md](docs/nvim.md)에 있습니다.

## 준비

```sh
npm install -g folocli@0.0.5
folo login
```

토큰은 CLI가 관리합니다. 플러그인은 토큰을 저장하지 않습니다. 환경변수 `FOLO_TOKEN`도 사용할 수 있습니다.

목록의 사이트 아이콘과 별표는 Nerd Font 글리프입니다. 터미널에 Nerd Font를 설정하지 않으면 빈칸이나 깨진 문자로 보입니다. 표에 없는 사이트는 도메인에서 딴 두 글자 배지로 표시합니다.

사이트별 아이콘과 색상의 기본 표는 `nvim/lua/folo/init.lua`의 `icons.domains`에 있습니다. 개인 항목은 `setup()` 옵션으로 추가합니다.

```lua
opts = {
  icons = {
    domains = {
      ["example.com"] = { "\u{f09e}", color = "#4c8bf5" }, -- 글리프와 색상
      ["example.org"] = { color = "#4c8bf5" }, -- 배지는 유지하고 색상만 지정
    },
  },
}
```

## 설치

```lua
-- lazy.nvim 예시
-- lazy는 저장소 루트만 불러오므로 하위 폴더를 runtimepath에 직접 추가합니다.
{ "wlsvy/PersonalToolsWithAI", name = "folo",
  cmd = { "Folo", "FoloUnread", "FoloStarred" },
  config = function(plugin)
    local dir = plugin.dir .. "/folo/nvim"
    vim.opt.rtp:append(dir)
    vim.cmd.source(dir .. "/plugin/folo.lua")
    require("folo").setup({})
  end }
```

rss 샘플도 함께 쓰면 같은 저장소 URL의 스펙은 lazy가 하나로 합치므로 스펙 하나에서 두 하위 폴더를 모두 불러와야 합니다.

전역 설치 없이 쓰려면 `opts = { cmd = { "npx", "--yes", "folocli@0.0.5" } }`로 지정합니다. 이 방식은 실행할 때마다 더 느릴 수 있습니다.

## 사용

| 명령 | 동작 |
|---|---|
| `:Folo` | 대시보드를 엽니다. 카테고리·피드별 안 읽은 개수를 보여 주고, `<CR>`로 해당 카테고리나 피드의 안 읽은 글을 엽니다. |
| `:FoloUnread` | 안 읽은 글을 엽니다. |
| `:FoloStarred` | 컬렉션에 저장한 글을 엽니다. |

모든 명령은 `Folo Dashboard` 탭 하나를 함께 씁니다. 맨 위 헤더에 `Dashboard (D)`, `Timeline (T)`, `Unread (U)`, `Starred (*)` 배지가 항상 보이고, 어느 화면에서든 그 키로 전환합니다. 목록은 왼쪽에 글 목록, 오른쪽에 미리보기를 엽니다. 커서를 옮기면 미리보기가 바뀌며, 이때는 읽음 처리하지 않습니다.

본문이 짧은 글은 Folo 추출, curl 순서로 원문을 가져와 피드 본문 아래에 덧붙입니다. curl로 읽지 못하는 페이지는 미리보기에서 `R`을 눌러 헤드리스 Chrome으로 렌더링합니다. Chrome은 매번 빈 프로필로 실행합니다. 자동 curl을 끄려면 `opts = { article = { auto_fetch = false } }`로 설정합니다.

AI 요약과 번역은 큐로 처리하며 기본 3개까지 동시에 실행합니다. 결과는 글 아래의 `└ summary` 자식 항목으로 표시되고, 커서를 올리면 미리보기에 내용이 나옵니다. 파일은 Neovim 캐시 폴더에 저장되어 재시작 후에도 남습니다. 크롬 확장과 같은 프롬프트와 전용 프로필을 쓰므로 `CLAUDE_CONFIG_DIR=~/.claude-clip claude`로 한 번 로그인되어 있어야 합니다. 자세한 내용은 [docs/ai.md](docs/ai.md)에 있습니다.

### 목록 화면

| 키 | 동작 |
|---|---|
| `<CR>` | 읽음으로 표시하고 미리보기로 이동합니다. |
| `<Tab>` | 글을 선택하거나 해제하고 아래로 이동합니다. 선택한 글은 맨 앞에 `+`로 표시합니다. |
| `m` | 선택한 글이나 현재 글의 읽음과 안 읽음을 전환합니다. 안 읽은 글이 하나라도 있으면 모두 읽음으로 바꿉니다. |
| `S` | 선택한 글이나 현재 글에 별표를 붙이거나 뗍니다. |
| `gx` | 선택한 글을 모두 브라우저로 엽니다. 선택이 없으면 현재 글을 엽니다. 10개를 넘으면 먼저 확인합니다. |
| `]p` | 다음 페이지를 불러옵니다. 커서가 목록 끝에서 5줄 안에 들어와도 자동으로 불러옵니다. |
| `r` | 목록을 새로 불러옵니다. |
| `s` | 선택한 글을 AI로 요약합니다. 선택이 없으면 현재 글을 요약합니다. |
| `t` | 번역을 요약 아래에 덧붙입니다. 요약이 없으면 요약부터 실행합니다. |
| `x` | 현재 글의 요약 파일을 삭제합니다. |
| `q` | 목록과 미리보기를 닫습니다. |
| `?` | 동작과 단축키 설명창을 열거나 닫습니다. |

### 미리보기 화면

| 키 | 동작 |
|---|---|
| `gx` | 원문을 브라우저로 엽니다. |
| `R` | 헤드리스 Chrome으로 렌더링한 원문을 표시합니다. |
| `q` | 목록으로 돌아갑니다. |
| `?` | 동작과 단축키 설명창을 열거나 닫습니다. |

본문 변환에는 pandoc을 쓰고, 없으면 태그만 제거합니다.

## 개발

```sh
nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/cli_test.lua
nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/article_test.lua
nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/ai_test.lua
```
