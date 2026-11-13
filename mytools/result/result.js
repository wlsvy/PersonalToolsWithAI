// openSummary()가 storage.session에 둔 { title, url, markdown, words }만 쓴다. 원래 탭에는 접근하지 않는다.
import { marked } from './vendor/marked.esm.js';
import { sourceLink } from '../features/summarize/summarize.js';

const HOST = 'com.personaltools.clip';

// LLM 출력은 웹 글에서 온 것이라 raw HTML은 태그로 해석하지 않고 글자로 보여준다 (스크립트는 확장 CSP가 어차피 막는다)
const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
marked.use({ renderer: { html: ({ text }) => escapeHtml(text) } });

async function render(el, md) {
  el.innerHTML = marked.parse(md);
  const blocks = el.querySelectorAll('pre > code.language-mermaid');
  if (!blocks.length) return;
  // 5MB라 mermaid 블록이 있을 때만 불러온다
  if (!globalThis.mermaid) {
    await new Promise((resolve, reject) => {
      const s = Object.assign(document.createElement('script'), { src: 'vendor/mermaid.min.js', onload: resolve, onerror: reject });
      document.head.append(s);
    });
    mermaid.initialize({ startOnLoad: false, securityLevel: 'strict' });
  }
  for (const code of blocks) {
    const div = Object.assign(document.createElement('div'), { className: 'mermaid', textContent: code.textContent });
    code.parentElement.replaceWith(div);
  }
  // 문법 오류인 블록은 mermaid가 오류 표시로 대신 그린다
  await mermaid.run({ nodes: el.querySelectorAll('.mermaid'), suppressErrors: true });
}
const $ = (id) => document.getElementById(id);
const status = $('status');
// busy면 스피너를 붙인다 (요약·번역 대기 중)
function setStatus(text, busy = false) {
  status.textContent = text;
  status.classList.toggle('busy', busy);
}
const key = new URLSearchParams(location.search).get('id');
const doc = await loadDoc();

// 사이드 패널은 추출보다 먼저 열려 데이터가 뒤늦게 들어온다. 리스너를 먼저 달아야 그 사이에 들어온 값을 놓치지 않는다.
// 브라우저 재시작 등으로 끝내 안 들어오면 undefined.
async function loadDoc() {
  let resolve;
  const arrived = new Promise((r) => (resolve = r));
  const onChanged = (changes, area) => {
    if (area === 'session' && changes[key]) resolve(changes[key].newValue);
  };
  chrome.storage.onChanged.addListener(onChanged);
  try {
    const { [key]: stored } = await chrome.storage.session.get(key);
    if (stored) return stored;
    setStatus('본문 추출 중…', true);
    return await Promise.race([arrived, new Promise((r) => setTimeout(r, 15000))]);
  } finally {
    chrome.storage.onChanged.removeListener(onChanged);
  }
}

// 호스트 응답과 같은 { ok, ... } 모양으로 맞춘다
async function ask(msg) {
  try {
    return await chrome.runtime.sendNativeMessage(HOST, msg);
  } catch (e) {
    const hint = /not found/i.test(e.message) ? ' — native-host/install.sh (Windows는 install.ps1) 를 먼저 실행하세요.' : '';
    return { ok: false, error: e.message + hint };
  }
}

if (!doc) {
  // 브라우저를 재시작하면 storage.session이 비워진다
  setStatus('데이터가 없습니다. 원래 페이지에서 다시 실행하세요.');
} else if (doc.error) {
  setStatus(doc.error);
} else {
  // 페이지 제목/본문은 외부 데이터라 textContent로만 넣는다
  document.title = `요약 · ${doc.title}`;
  $('title').textContent = doc.title;
  $('url').textContent = $('url').href = doc.url;
  $('words').textContent = `WordCount: ${doc.words}`;
  $('source').textContent = doc.markdown;

  // 새로고침마다 다시 요약하지 않도록 결과를 같은 키에 붙여 둔다
  if (!doc.summary) {
    setStatus('요약 중… (sonnet)', true);
    const r = await ask({ action: 'summary', url: doc.url, markdown: doc.markdown });
    if (r.ok) {
      doc.summary = r.text;
      await chrome.storage.session.set({ [key]: doc });
    } else {
      setStatus(`요약 실패: ${r.error}`);
    }
  }
  if (doc.summary) {
    setStatus('');
    await render($('summary'), summaryMd());
    $('copy').disabled = false;
  }
  if (doc.translation) await showTranslation();
  else $('translate').disabled = false;
}

// 링크는 저장하지 않고 표시·복사 때 붙인다 — 이미 저장된 요약에도 붙도록
function summaryMd() {
  return `${sourceLink(doc.title, doc.url)}\n\n${doc.summary}`;
}

async function showTranslation() {
  await render($('translation'), doc.translation);
  $('copy-translation').disabled = false;
}

// 상태 줄과 따로 띄운다 — 번역 중 복사해도 진행 표시가 지워지지 않게
let toastTimer;
async function copy(text) {
  try {
    await navigator.clipboard.writeText(text);
    $('toast').textContent = `복사했습니다 (${text.length}자)`;
  } catch (e) {
    $('toast').textContent = `복사 실패: ${e.message}`;
  }
  $('toast').classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => $('toast').classList.remove('show'), 2000);
}

$('copy').addEventListener('click', () => copy(summaryMd()));
$('copy-translation').addEventListener('click', () => copy(doc.translation));

$('translate').addEventListener('click', async () => {
  $('translate').disabled = true;
  setStatus('번역 중… (sonnet, 긴 글은 몇 분 걸립니다)', true);
  const r = await ask({ action: 'translate', markdown: doc.markdown });
  if (!r.ok) {
    setStatus(`번역 실패: ${r.error}`);
    $('translate').disabled = false;
    return;
  }
  setStatus('');
  // 요약과 같이 새로고침해도 다시 번역하지 않게 붙여 둔다
  doc.translation = r.text;
  await chrome.storage.session.set({ [key]: doc });
  await showTranslation();
});
