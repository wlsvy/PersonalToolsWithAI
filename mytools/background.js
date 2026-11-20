import { toggleGrayscale } from './features/grayscale/grayscale.js';
import { clipMarkdown, appendMarkdown } from './features/clip-markdown/clip-markdown.js';
import { openSummary, openSummaryPanel, fillSummary } from './features/summarize/summarize.js';
import { rememberClip } from './features/clip-history/clip-history.js';

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
  'clip-append': {
    title: '본문 Markdown 이어 붙이기',
    run: async (tab) => {
      const md = await clipMarkdown(tab.id);
      if (md) await copyText(md, { append: true });
    },
  },
  'copy-tab-urls': {
    title: '선택한 탭 URL 복사',
    // 'all'에는 탭 표시줄 메뉴('tab')가 포함되지 않는다
    contexts: ['all', 'tab'],
    run: async (tab) => {
      // Cmd/Shift+클릭으로 고른 탭들. 선택 밖의 탭을 우클릭했으면 그 탭만 복사한다
      const tabs = tab?.highlighted === false
        ? [tab]
        : await chrome.tabs.query({ highlighted: true, windowId: tab?.windowId ?? chrome.windows.WINDOW_ID_CURRENT });
      await copyText(tabs.map((t) => t.url).join('\n'));
    },
  },
  summary: { title: '요약·번역 (새 탭)', run: (tab) => openSummary(tab) },
  'summary-panel': {
    title: '요약·번역 (사이드 패널)',
    run: async (tab) => {
      const { key, opened } = openSummaryPanel(tab);
      tab ??= (await chrome.tabs.query({ active: true, currentWindow: true }))[0];
      await Promise.all([opened, fillSummary(key, tab)]);
    },
  },
};

chrome.runtime.onInstalled.addListener(async () => {
  const keys = await shortcuts();
  for (const [id, { title, contexts = ['all'] }] of Object.entries(MENUS)) {
    chrome.contextMenus.create({ id, title: withKey(title, keys[id]), contexts });
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

// chrome:// 등 주입 불가 페이지에서는 실패하는데, 알릴 UI가 없어 service worker 콘솔에만 남긴다
chrome.contextMenus.onClicked.addListener((info, tab) => {
  MENUS[info.menuItemId]?.run(tab).catch((e) => console.error(info.menuItemId, e));
});

// 단축키(manifest commands) → 같은 id의 메뉴 기능 실행
// Dia는 tab을 넘기지 않으므로(undefined) 각 run이 처리한다
chrome.commands.onCommand.addListener((command, tab) => {
  MENUS[command]?.run(tab).catch((e) => console.error(command, e));
});

// popup [사이드 패널 요약]은 패널을 열면 닫히므로 추출은 여기 맡긴다
chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === 'summary-panel') fillSummary(msg.key, msg.tab);
  if (msg.type === 'clip-history') rememberClip(msg.text);
});

// service worker에는 navigator.clipboard가 없어 offscreen 문서에서 쓴다
async function copyText(text, { append = false } = {}) {
  await chrome.offscreen.createDocument({
    url: 'offscreen/offscreen.html',
    reasons: ['CLIPBOARD'],
    justification: '추출한 본문을 클립보드에 쓰기(이어 붙일 때는 기존 내용 읽기)',
  });
  try {
    if (append) text = appendMarkdown(await chrome.runtime.sendMessage({ type: 'paste' }), text);
    await chrome.runtime.sendMessage({ type: 'copy', text });
    await rememberClip(text);
  } finally {
    await chrome.offscreen.closeDocument();
  }
}
