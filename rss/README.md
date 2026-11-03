# RSS 리더

셀프호스트 RSS 서버(Go)와 웹앱(Vue PWA), nvim 플러그인입니다. 설계는 [docs/plan.md](docs/plan.md)에 있습니다.

## 서버 + 웹앱 실행

```sh
cd rss/web && npm ci && npm run build
cd ../server && go build -o rss-server ./cmd/rss-server
RSS_TOKEN=<토큰> RSS_WEB_DIR=../web/dist ./rss-server
```

- 브라우저에서 http://127.0.0.1:8080 을 열고 설정 화면에 토큰을 입력합니다.
- 설정 항목은 [docs/config.md](docs/config.md)에 있습니다.

## 폰에서 접속 (Tailscale)

```sh
tailscale serve --bg 8080
```

폰에서 `https://<mac 이름>.<tailnet>.ts.net`을 열고 홈 화면에 추가합니다.

## nvim

```lua
-- lazy.nvim 예시
{ dir = "~/Desktop/Workspace/PersonalToolsWithAI/rss/nvim", config = function()
  require("rss").setup({ url = "http://127.0.0.1:8080", token = vim.env.RSS_TOKEN })
end }
```

명령은 `:Rss`, `:RssUnread`, `:RssAdd <url>`, `:RssRefresh [id]`입니다. 본문 변환에는 pandoc을 쓰고, 없으면 태그만 제거합니다.

## 개발

```sh
cd rss/server && go test ./...
cd rss/web && npm test && npm run typecheck
cd rss/web && npm run dev   # /api는 RSS_DEV_SERVER(기본 127.0.0.1:8080)로 프록시합니다
nvim --headless -u NONE --cmd "set rtp+=rss/nvim" -l rss/nvim/tests/render_test.lua
```

## 보안 메모

- 피드 본문 HTML은 서버가 저장할 때 정리합니다(bluemonday). 웹앱은 CSP로 한 번 더 막습니다.
- 토큰은 웹앱의 localStorage에 저장됩니다.
