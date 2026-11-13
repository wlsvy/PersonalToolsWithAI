import { toggleGrayscale } from './features/grayscale/grayscale.js';
import { clipMarkdown } from './features/clip-markdown/clip-markdown.js';
import { openSummary, openSummaryPanel, fillSummary } from './features/summarize/summarize.js';

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
  'summary-panel': {
    title: '요약·번역 (사이드 패널)',
    run: async (tab) => {
      const { key, opened } = openSummaryPanel(tab);
      await Promise.all([opened, fillSummary(key, tab)]);
    },
  },
};

chrome.runtime.onInstalled.addListener(async () => {
  const keys = await shortcuts();
  for (const [id, { title }] of Object.entries(MENUS)) {
    chrome.contextMenus.create({ id, title: withKey(title, keys[id]), contexts: ['all'] });
  }
});

// ponytail: 단축키 변경 이벤트가 없어 브라우저 시작 때만 제목을 갱신한다
chrome.runtime.onStartup.addListener(async () => {
  const keys = await shortcuts();
  for (const [id, { title }] of Object.entries(MENUS)) {
    chrome.contextMenus.update(id, { title: withKey(title, keys[id]) });
  }
});

// 명령 id → 사용자가 지정한 실제 단축키 (미지정이면 빈 문자열)
async function shortcuts() {
  const cmds = await chrome.commands.getAll();
  return Object.fromEntries(cmds.map((c) => [c.name, c.shortcut]));
}

const withKey = (title, key) => (key ? `${title}  [${key}]` : title);

// chrome:// 등 주입 불가 페이지에서는 실패하는데, 알릴 UI가 없어 무시한다
chrome.contextMenus.onClicked.addListener((info, tab) => {
  MENUS[info.menuItemId]?.run(tab).catch(() => {});
});

// 단축키(manifest commands) → 같은 id의 메뉴 기능 실행
chrome.commands.onCommand.addListener((command, tab) => {
  MENUS[command]?.run(tab).catch(() => {});
});

// popup [사이드 패널 요약]은 패널을 열면 닫히므로 추출은 여기 맡긴다
chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === 'summary-panel') fillSummary(msg.key, msg.tab);
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
