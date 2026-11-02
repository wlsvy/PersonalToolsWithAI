import { clipMarkdown } from '../clip-markdown/clip-markdown.js';

// 탭 본문을 추출해 storage.session에 두고 결과 탭을 연다. 결과 탭은 원래 탭 없이 이 데이터만 쓴다.
// active: false면 현재 탭에 포커스를 둔 채 뒤에서 연다
export async function openSummary({ id, title, url }, { active = true } = {}) {
  const markdown = stripLinkTitles(await clipMarkdown(id));
  if (!markdown) throw new Error('본문을 찾지 못했습니다.');
  const key = crypto.randomUUID();
  await chrome.storage.session.set({ [key]: { title, url, markdown, words: countWords(markdown) } });
  await chrome.tabs.create({ url: chrome.runtime.getURL(`result/result.html?id=${key}`), active });
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

// 요약 상단·복사본에 붙일 원문 링크. LLM에 맡기지 않고 코드로 만든다 (URL을 틀리게 옮길 수 있어서).
// 제목의 [ ]와 URL의 ( ) 공백이 Markdown 링크를 끊지 않게 이스케이프한다.
export function sourceLink(title, url) {
  const text = title.replace(/[\\[\]]/g, '\\$&');
  const href = url.replace(/[()\s]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0')}`);
  return `[${text}](${href})`;
}
