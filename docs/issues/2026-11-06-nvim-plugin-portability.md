# nvim 플러그인 로컬 경로 의존과 이식성 점검

- 날짜: 2026-11-06
- 대상: `folo/nvim`, `rss/nvim-sample`

## 증상

lazy.nvim이 두 플러그인을 불러오지 못했습니다.

```
folo        Local plugin does not exist at `C:/Users/jinpyo.kim/Desktop/Workspace/PersonalToolsWithAI/folo/nvim`
rss_sample  Local plugin does not exist at `C:/Users/jinpyo.kim/Desktop/Workspace/PersonalToolsWithAI/rss/nvim-sample`
```

## 원인

nvim 설정의 플러그인 스펙이 `dir = "~/Desktop/Workspace/..."` 로컬 경로를 가리켰습니다. 저장소는 `C:/Workspace/PersonalToolsWithAI`에 있어 경로가 맞지 않았습니다. README 설치 예시도 같은 경로를 쓰고 있었습니다.

## 조치

### nvim 설정 (저장소 밖)

로컬 경로 대신 GitHub 저장소 `wlsvy/PersonalToolsWithAI`를 lazy가 받아 오도록 바꿨습니다. 코드를 원격에 푸시한 뒤 `:Lazy update`로 반영합니다.

- lazy는 저장소 루트만 플러그인으로 불러옵니다. `config`에서 하위 폴더를 runtimepath에 추가하고 `plugin/*.lua`를 직접 source합니다.
- lazy는 URL이 같은 스펙을 하나로 합칩니다. 스펙을 둘로 두면 하나가 사라지므로 `lua/plugins/personal_tools.lua` 스펙 하나에서 두 하위 폴더를 모두 불러옵니다.

### 저장소

| 파일 | 내용 |
|---|---|
| `folo/README.md`, `rss/README.md` | 설치 예시를 로컬 경로에서 GitHub 스펙 방식으로 바꿨습니다. |
| `folo/nvim/lua/folo/article.lua` | 헤드리스 렌더용 브라우저 후보에 Windows Chrome과 Edge 경로를 추가했습니다. 이전에는 macOS와 Linux 이름만 찾았습니다. |
| `folo/nvim/lua/folo/cli.lua`, `ai.lua` | Windows에서 `folo`, `claude`가 npm `.cmd` shim이면 그 경로로 실행합니다. `npm install -g folocli` 후 `vim.system({"folo", ...})`가 ENOENT로 실패했습니다. `exepath("folo")`는 확장자 없는 sh shim을 돌려주므로 쓰지 않습니다. |

## 점검 결과 중 남겨 둔 것

| 위치 | 내용 | 남겨 둔 이유 |
|---|---|---|
| `folo/nvim/lua/folo/ai.lua:7` | 프롬프트를 `native-host/prompts/`에서 읽습니다. | lazy가 저장소 전체를 받으므로 동작합니다. 플러그인 안으로 복사하면 두 벌이 따로 놉니다. |
| `folo/nvim/lua/folo/init.lua:23` | `config_dir` 기본값이 `~/.claude-clip`입니다. | 크롬 확장과 프로필을 공유하려는 의도입니다. `ai.config_dir`로 바꿀 수 있습니다. |
| `folo/nvim/lua/folo/ai.lua:92` | 번역 제목이 `## 번역`으로 고정되어 있습니다. | 번역 대상 언어가 한국어 하나뿐입니다. |
| `folo/nvim/tests/` | 테스트가 `/bin/sh`를 씁니다. | Windows에서 테스트를 돌릴 일이 생기면 고칩니다. |

코드에 사용자 이름, 드라이브 문자, 특정 피드나 카테고리를 고정한 곳은 없었습니다.
