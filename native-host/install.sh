#!/bin/sh
# 사용법: ./install.sh <확장 ID>   (chrome://extensions 에서 확인. 압축해제 확장은 폴더 경로마다 ID가 다르다)
set -e
[ -n "$1" ] || { echo "usage: $0 <extension-id>"; exit 1; }
NODE="$(command -v node)" || { echo "node를 찾지 못했습니다."; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
HOST="$DEST/com.personaltools.clip.sh"
mkdir -p "$DEST"
# Chrome이 Dock에서 실행되면 PATH가 /usr/bin:/bin 뿐이라 node 절대 경로를 기록한 wrapper로 실행한다.
# node 경로가 바뀌면(nvm 등) 이 스크립트를 다시 실행한다.
printf '#!/bin/sh\nexec "%s" "%s/clip_host.mjs"\n' "$NODE" "$DIR" > "$HOST"
chmod +x "$HOST"
cat > "$DEST/com.personaltools.clip.json" <<EOF
{
  "name": "com.personaltools.clip",
  "description": "PersonalToolsWithAI: claude -p 요약·번역",
  "path": "$HOST",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$1/"]
}
EOF
echo "설치됨: $DEST/com.personaltools.clip.json (node: $NODE)"
