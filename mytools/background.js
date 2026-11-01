import { toggleGrayscale } from './features/grayscale/grayscale.js';
import { clipMarkdown } from './features/clip-markdown/clip-markdown.js';
import { openSummary } from './features/summarize/summarize.js';

// 우클릭 메뉴 id → 제목, 실행 함수
const MENUS = {
  grayscale: { title: '흑백 전환', run: (tab) => toggleGrayscale(tab.id) },
  clip: {
    title: '본문 Markdown 복사',
    run: async (tab) => {
      const md = await clipMarkdown(tab.id);
      // 본문을 못 찾았으면 기존 클립보드를 비우지 않는다
      if (md) await copyText(md);
    },
  },
  summary: { title: '요약·번역 (새 탭)', run: (tab) => openSummary(tab) },
};

chrome.runtime.onInstalled.addListener(() => {
  for (const [id, { title }] of Object.entries(MENUS)) {
    chrome.contextMenus.create({ id, title, contexts: ['all'] });
  }
});

// chrome:// 등 주입 불가 페이지에서는 실패하는데, 알릴 UI가 없어 무시한다
chrome.contextMenus.onClicked.addListener((info, tab) => {
  MENUS[info.menuItemId]?.run(tab).catch(() => {});
});

// service worker에는 navigator.clipboard가 없어 offscreen 문서에서 쓴다
async function copyText(text) {
  await chrome.offscreen.createDocument({
    url: 'offscreen/offscreen.html',
    reasons: ['CLIPBOARD'],
    justification: '추출한 본문을 클립보드에 쓰기',
  });
  try {
    await chrome.runtime.sendMessage({ type: 'copy', text });
  } finally {
    await chrome.offscreen.closeDocument();
  }
}
