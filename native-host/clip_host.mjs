// Chrome Native Messaging 호스트. 확장이 보낸 본문을 claude -p로 요약·번역해 돌려준다.
// Chrome이 Dock에서 실행되면 PATH가 /usr/bin:/bin 뿐이라 install.sh(Windows는 install.ps1)가 만든 wrapper가 node 절대 경로로 실행한다.
import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { delimiter, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const IS_WIN = process.platform === 'win32';
const BINS = IS_WIN ? ['claude.exe', 'claude.cmd', 'claude'] : ['claude'];
const DIRS = [
  ...(process.env.PATH ?? '').split(delimiter),
  ...(IS_WIN
    ? [
        process.env.LOCALAPPDATA && join(process.env.LOCALAPPDATA, 'Microsoft', 'WinGet', 'Links'),
        process.env.APPDATA && join(process.env.APPDATA, 'npm'),
        join(homedir(), '.local', 'bin'),
      ]
    : ['/opt/homebrew/bin', '/usr/local/bin', join(homedir(), '.local', 'bin')]),
].filter(Boolean);
const CLAUDE = DIRS.flatMap((dir) => BINS.map((bin) => join(dir, bin))).find(existsSync);

// 메시지 형식: 4바이트 길이(native byte order — macOS/Windows x64·ARM64는 little-endian) + UTF-8 JSON
async function readMsg() {
  let buf = Buffer.alloc(0);
  for await (const chunk of process.stdin) {
    buf = Buffer.concat([buf, chunk]);
    if (buf.length >= 4 && buf.length >= 4 + buf.readUInt32LE(0)) break;
  }
  if (buf.length < 4) process.exit(0);
  return JSON.parse(buf.subarray(4, 4 + buf.readUInt32LE(0)));
}

function sendMsg(obj) {
  const data = Buffer.from(JSON.stringify(obj));
  const len = Buffer.alloc(4);
  len.writeUInt32LE(data.length);
  process.stdout.write(Buffer.concat([len, data]));
}

function ask(model, prompt, text) {
  if (!CLAUDE) throw new Error('claude CLI를 찾지 못했습니다.');
  // --tools '': 입력이 신뢰할 수 없는 웹 본문이라 도구를 모두 끈다.
  // --setting-sources '' + --strict-mcp-config: 기본 로그인은 쓰되 전역 CLAUDE.md·플러그인·hook·MCP는 섞지 않는다.
  // cwd를 임시 폴더로: 이 저장소의 CLAUDE.md/.claude가 읽히지 않게
  const r = spawnSync(
    CLAUDE,
    ['-p', '--model', model, '--system-prompt', readFileSync(join(HERE, 'prompts', prompt), 'utf8'),
      '--tools', '', '--no-session-persistence', '--setting-sources', '', '--strict-mcp-config'],
    { input: text, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, cwd: tmpdir() },
  );
  if (r.error) throw r.error;
  if (r.status !== 0) throw new Error((r.stderr || r.stdout).trim() || `claude exit ${r.status}`);
  return r.stdout.trim();
}

// prompts/sites/<키워드>.md가 있으면 summary.md 대신 쓴다(오버라이드).
// 호스트 이름을 '.' 단위로 나눠 비교해 www.hankyung.com은 맞고 nothankyung.com은 안 맞게 한다.
export function summaryPrompt(url) {
  let labels;
  try {
    labels = new URL(url).hostname.split('.');
  } catch {
    return 'summary.md';
  }
  const key = readdirSync(join(HERE, 'prompts', 'sites'))
    .map((f) => f.replace(/\.md$/, ''))
    .find((k) => labels.includes(k));
  return key ? join('sites', `${key}.md`) : 'summary.md';
}

function handle(msg) {
  if (msg.action === 'summary') return { ok: true, text: ask('sonnet', summaryPrompt(msg.url), msg.markdown) };
  if (msg.action === 'translate') return { ok: true, text: ask('sonnet', 'translate.md', msg.markdown) };
  return { ok: false, error: `unknown action: ${JSON.stringify(msg.action)}` };
}

// import(테스트)할 때는 실행하지 않는다
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    sendMsg(handle(await readMsg()));
  } catch (e) {
    // 확장에 알릴 수 있게 모든 실패를 응답으로 돌려준다
    sendMsg({ ok: false, error: e.message });
  }
}
