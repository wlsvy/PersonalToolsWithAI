import { clipMarkdown } from '../clip-markdown/clip-markdown.js';

// 탭 본문을 추출해 storage.session에 두고 결과 탭을 연다. 결과 탭은 원래 탭 없이 이 데이터만 쓴다.
export async function openSummary({ id, title, url }) {
  const markdown = stripLinkTitles(await clipMarkdown(id));
  if (!markdown) throw new Error('본문을 찾지 못했습니다.');
  const key = crypto.randomUUID();
  await chrome.storage.session.set({ [key]: { title, url, markdown, words: countWords(markdown) } });
  await chrome.tabs.create({ url: chrome.runtime.getURL(`result/result.html?id=${key}`) });
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
