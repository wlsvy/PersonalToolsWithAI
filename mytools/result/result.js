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
const key = new URLSearchParams(location.search).get('id');
const { [key]: doc } = await chrome.storage.session.get(key);

// 호스트 응답과 같은 { ok, ... } 모양으로 맞춘다
async function ask(msg) {
  try {
    return await chrome.runtime.sendNativeMessage(HOST, msg);
  } catch (e) {
    const hint = /not found/i.test(e.message) ? ' — native-host/install.sh 를 먼저 실행하세요.' : '';
    return { ok: false, error: e.message + hint };
  }
}

if (!doc) {
  // 브라우저를 재시작하면 storage.session이 비워진다
  status.textContent = '데이터가 없습니다. 원래 페이지에서 다시 실행하세요.';
} else {
  // 페이지 제목/본문은 외부 데이터라 textContent로만 넣는다
  document.title = `요약 · ${doc.title}`;
  $('title').textContent = doc.title;
  $('url').textContent = $('url').href = doc.url;
  $('words').textContent = `WordCount: ${doc.words}`;
  $('source').textContent = doc.markdown;

  // 새로고침마다 다시 요약하지 않도록 결과를 같은 키에 붙여 둔다
  if (!doc.summary) {
    status.textContent = '요약 중… (sonnet)';
    const r = await ask({ action: 'summary', markdown: doc.markdown });
    if (r.ok) {
      doc.summary = r.text;
      await chrome.storage.session.set({ [key]: doc });
    } else {
      status.textContent = `요약 실패: ${r.error}`;
    }
  }
  if (doc.summary) {
    status.textContent = '';
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

async function copy(text) {
  await navigator.clipboard.writeText(text);
  status.textContent = `복사했습니다 (${text.length}자).`;
}

$('copy').addEventListener('click', () => copy(summaryMd()));
$('copy-translation').addEventListener('click', () => copy(doc.translation));

$('translate').addEventListener('click', async () => {
  $('translate').disabled = true;
  status.textContent = '번역 중… (sonnet, 긴 글은 몇 분 걸립니다)';
  const r = await ask({ action: 'translate', markdown: doc.markdown });
  if (!r.ok) {
    status.textContent = `번역 실패: ${r.error}`;
    $('translate').disabled = false;
    return;
  }
  status.textContent = '';
  // 요약과 같이 새로고침해도 다시 번역하지 않게 붙여 둔다
  doc.translation = r.text;
  await chrome.storage.session.set({ [key]: doc });
  await showTranslation();
});
