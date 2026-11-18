import { toggleGrayscale } from '../features/grayscale/grayscale.js';
import { listTabs, urlList, markdownList } from '../features/tab-list/tab-list.js';
import { clipMarkdown, appendMarkdown } from '../features/clip-markdown/clip-markdown.js';
import { openSummary, openSummaryPanel } from '../features/summarize/summarize.js';
import { recentClips, rememberClip } from '../features/clip-history/clip-history.js';

const status = document.getElementById('status');

async function clip(append) {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  let md;
  try {
    md = await clipMarkdown(tab.id);
  } catch {
    status.textContent = '이 페이지에서는 사용할 수 없습니다.';
    return;
  }
  if (!md) {
    status.textContent = '본문을 찾지 못했습니다.';
    return;
  }
  // popup이 포커스를 가진 쪽이라 페이지가 아니라 여기서 쓴다
  if (append) {
    const all = appendMarkdown(await navigator.clipboard.readText(), md);
    await navigator.clipboard.writeText(all);
    await rememberClip(all);
    renderHistory();
    status.textContent = `이어 붙였습니다 (+${md.length}자, 총 ${all.length}자).`;
    return;
  }
  await navigator.clipboard.writeText(md);
  await rememberClip(md);
  renderHistory();
  status.textContent = `복사했습니다 (${md.length}자).`;
}
document.getElementById('clip').addEventListener('click', () => clip(false));
document.getElementById('clip-append').addEventListener('click', () => clip(true));

// sidePanel.open()은 사용자 제스처 안에서만 되므로 클릭 뒤에는 await하지 않는다. 그래서 활성 탭을 미리 구해 둔다.
const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
document.getElementById('summary-panel').addEventListener('click', () => {
  // chrome:// 등은 Chrome 정책상 주입 불가
  if (!/^https?:/.test(activeTab.url ?? '')) {
    status.textContent = '이 페이지에서는 사용할 수 없습니다.';
    return;
  }
  const { key, opened } = openSummaryPanel(activeTab);
  const { id, title, url } = activeTab;
  chrome.runtime.sendMessage({ type: 'summary-panel', key, tab: { id, title, url } });
  opened.then(
    () => window.close(),
    (e) => { status.textContent = `사이드 패널을 열지 못했습니다: ${e.message}`; },
  );
});

document.getElementById('grayscale').addEventListener('click', async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  try {
    await toggleGrayscale(tab.id);
    status.textContent = '';
  } catch {
    // chrome:// 페이지, 웹 스토어 등은 Chrome 정책상 주입 불가
    status.textContent = '이 페이지에서는 사용할 수 없습니다.';
  }
});

// 다른 앱에서 복사한 것은 이벤트로 잡을 수 없어, popup을 열 때 현재 클립보드를 기록한다
try {
  await rememberClip(await navigator.clipboard.readText());
} catch {
  // 포커스를 잃는 등으로 읽기가 실패하면 기존 기록만 보여 준다
}
const history = document.getElementById('history');
async function renderHistory() {
  const items = await recentClips();
  history.replaceChildren(...items.map((text) => {
    const li = document.createElement('li');
    const t = document.createElement('div');
    const btn = document.createElement('button');
    t.className = 'text clip';
    t.textContent = text;
    t.title = text.slice(0, 500);
    btn.type = 'button';
    btn.textContent = '복사';
    btn.setAttribute('aria-label', `복사: ${text.slice(0, 40)}`);
    btn.addEventListener('click', async () => {
      await navigator.clipboard.writeText(text);
      await rememberClip(text);
      status.textContent = `복사했습니다 (${text.length}자).`;
      renderHistory();
    });
    li.append(t, btn);
    return li;
  }));
}
await renderHistory();

// 페이지 제목/URL은 외부 데이터라 textContent로만 넣는다
const list = document.getElementById('tabs');
const allBox = document.getElementById('tab-all');
const copyButtons = [document.getElementById('copy-md'), document.getElementById('copy-urls')];
const rows = []; // { tab, box }
const picked = () => rows.filter((r) => r.box.checked).map((r) => r.tab);
function updateSelection() {
  const n = picked().length;
  document.getElementById('tab-count').textContent = `${n}/${rows.length}`;
  allBox.checked = n === rows.length;
  allBox.indeterminate = n > 0 && n < rows.length;
  for (const b of copyButtons) b.disabled = n === 0;
}
allBox.addEventListener('change', () => {
  for (const r of rows) r.box.checked = allBox.checked;
  updateSelection();
});
async function copyTabs(format) {
  const tabs = picked();
  const text = format(tabs);
  await navigator.clipboard.writeText(text);
  await rememberClip(text);
  renderHistory();
  status.textContent = `탭 ${tabs.length}개를 복사했습니다.`;
}
copyButtons[0].addEventListener('click', () => copyTabs(markdownList));
copyButtons[1].addEventListener('click', () => copyTabs(urlList));

for (const tab of await listTabs()) {
  const li = document.createElement('li');
  const text = document.createElement('label');
  const box = document.createElement('input');
  const info = document.createElement('div');
  const t = document.createElement('div');
  const u = document.createElement('div');
  const btn = document.createElement('button');
  text.className = 'text';
  t.className = 'title';
  u.className = 'url';
  t.textContent = tab.title;
  u.textContent = tab.url;
  btn.type = 'button';
  btn.textContent = '요약';
  btn.setAttribute('aria-label', `요약: ${tab.title}`);
  // chrome:// 등은 Chrome 정책상 주입 불가
  btn.disabled = !/^https?:/.test(tab.url);
  btn.addEventListener('click', async () => {
    status.textContent = '본문 추출 중…';
    try {
      // 뒤에서 열어 popup이 닫히지 않으니 여러 탭을 연달아 요약할 수 있다
      await openSummary(tab, { active: false });
      status.textContent = `새 탭에서 요약 중: ${tab.title}`;
    } catch (e) {
      // 메모리 절약으로 언로드된 탭도 주입이 실패한다
      status.textContent = e.message === '본문을 찾지 못했습니다.' ? e.message : '이 탭에서는 사용할 수 없습니다. 탭을 한 번 열어 로드한 뒤 다시 시도하세요.';
    }
  });
  // 브라우저에서 Ctrl/Shift+클릭으로 여러 탭을 골라 두었으면 그 탭들을 미리 체크한다
  box.type = 'checkbox';
  box.checked = tab.highlighted;
  box.addEventListener('change', updateSelection);
  rows.push({ tab, box });
  info.append(t, u);
  text.append(box, info);
  li.append(text, btn);
  list.append(li);
}
updateSelection();
