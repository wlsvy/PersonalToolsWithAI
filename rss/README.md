# RSS 리더

셀프호스트 RSS 서버(Go)와 웹앱(Vue PWA), 학습용 nvim 샘플 플러그인입니다. 설계는 [docs/plan.md](docs/plan.md)에 있습니다.

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

## nvim (학습용 샘플)

```lua
-- lazy.nvim 예시
{ dir = "~/Desktop/Workspace/PersonalToolsWithAI/rss/nvim-sample", config = function()
  require("rss_sample").setup({ url = "http://127.0.0.1:8080", token = vim.env.RSS_TOKEN })
end }
```

명령은 `:RssSample`, `:RssSampleUnread`, `:RssSampleAdd <url>`, `:RssSampleRefresh [id]`입니다. 본문 변환에는 pandoc을 쓰고, 없으면 태그만 제거합니다.

## 개발

```sh
cd rss/server && go test ./...
cd rss/web && npm test && npm run typecheck
cd rss/web && npm run dev   # /api는 RSS_DEV_SERVER(기본 127.0.0.1:8080)로 프록시합니다
nvim --headless -u NONE --cmd "set rtp+=rss/nvim-sample" -l rss/nvim-sample/tests/render_test.lua
```

## 보안 메모

- 피드 본문 HTML은 서버가 저장할 때 정리합니다(bluemonday). 웹앱은 CSP로 한 번 더 막습니다.
- 글 링크는 http/https만 남기고, 내부망 주소(127.0.0.1, 192.168.x, 169.254.x, Tailscale 100.x 등)의 피드는 기본으로 가져오지 않습니다. 로컬 RSSHub 같은 내부 피드를 쓰려면 `RSS_ALLOW_PRIVATE_FETCH=1`을 설정합니다. 차단 모드에서는 `HTTPS_PROXY` 같은 프록시 설정을 무시합니다.
- 웹앱 CSP는 `index.html`의 meta 태그로만 적용합니다(HTTP 헤더는 보내지 않습니다).
- 토큰은 웹앱의 localStorage에 저장됩니다.
