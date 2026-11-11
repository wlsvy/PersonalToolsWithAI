import { clipMarkdown } from '../clip-markdown/clip-markdown.js';

// 탭 본문을 추출해 storage.session에 두고 결과 탭을 연다. 결과 탭은 원래 탭 없이 이 데이터만 쓴다.
// active: false면 현재 탭에 포커스를 둔 채 뒤에서 연다
export async function openSummary(tab, { active = true } = {}) {
  const key = crypto.randomUUID();
  await chrome.storage.session.set({ [key]: await extractDoc(tab) });
  await chrome.tabs.create({ url: chrome.runtime.getURL(`result/result.html?id=${key}`), active });
}

// 같은 결과 페이지를 그 탭의 사이드 패널에 연다. open()은 사용자 제스처 안에서만 되므로 await 없이 바로 부른다.
// 본문은 아직 없다 — 호출한 쪽이 key로 fillSummary()를 이어서 부른다.
export function openSummaryPanel(tab) {
  const key = crypto.randomUUID();
  chrome.sidePanel.setOptions({ tabId: tab.id, path: `result/result.html?id=${key}`, enabled: true });
  return { key, opened: chrome.sidePanel.open({ tabId: tab.id }) };
}

// 결과 페이지는 키가 채워질 때까지 기다리므로, 실패도 { error }로 같은 키에 넣어 알린다
export async function fillSummary(key, tab) {
  let doc;
  try {
    doc = await extractDoc(tab);
  } catch (e) {
    // chrome:// 등 주입 불가 페이지, 언로드된 탭
    doc = { error: e.message === NOT_FOUND ? e.message : '이 페이지에서는 사용할 수 없습니다.' };
  }
  await chrome.storage.session.set({ [key]: doc });
}

const NOT_FOUND = '본문을 찾지 못했습니다.';

async function extractDoc({ id, title, url }) {
  const markdown = stripCitations(stripLinkTitles(await clipMarkdown(id)));
  if (!markdown) throw new Error(NOT_FOUND);
  return { title, url, markdown, words: countWords(markdown) };
}

// LLM은 단어 수를 정확히 못 세서 코드로 센다
export function countWords(text) {
  return text.split(/\s+/).filter(Boolean).length;
}

// 논문의 참고문헌 링크 [1](url "저자, 제목…")에서 title만 지운다 — 토큰·단어 수가 크게 부풀어서.
// turndown은 URL의 괄호와 title의 따옴표를 \ 로 이스케이프한다.
export function stripLinkTitles(md) {
  return md.replace(/(\]\((?:[^()\s\\]|\\.)*) "(?:[^"\\]|\\.)*"\)/g, '$1)');
}

// 본문의 인용 번호 링크 [1](…#ref-CR1),[2](…) 묶음을 통째로 지운다 — 요약·번역에 남으면 읽기 거슬려서.
// 위키백과식 [\[1\]](…)도 포함. shortcut: 텍스트가 숫자뿐인 링크는 모두 인용으로 본다, 본문에 숫자 링크가 남아야 하면 href 조건 추가.
const CITE = String.raw`\[(?:\\\[)?\d+(?:[–-]\d+)?(?:\\\])?\]\((?:[^()\s\\]|\\.)*\)`;
export function stripCitations(md) {
  return md.replace(new RegExp(`${CITE}(?:\\s*[,–-]\\s*${CITE})*`, 'g'), '');
}

// 요약 상단·복사본에 붙일 원문 링크. LLM에 맡기지 않고 코드로 만든다 (URL을 틀리게 옮길 수 있어서).
// 제목의 [ ]와 URL의 ( ) 공백이 Markdown 링크를 끊지 않게 이스케이프한다.
export function sourceLink(title, url) {
  const text = title.replace(/[\\[\]]/g, '\\$&');
  const href = url.replace(/[()\s]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0')}`);
  return `[${text}](${href})`;
}
