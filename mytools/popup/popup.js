import { toggleGrayscale } from '../features/grayscale/grayscale.js';
import { listTabs } from '../features/tab-list/tab-list.js';
import { clipMarkdown } from '../features/clip-markdown/clip-markdown.js';
import { openSummary } from '../features/summarize/summarize.js';

const status = document.getElementById('status');

document.getElementById('clip').addEventListener('click', async () => {
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
  await navigator.clipboard.writeText(md);
  status.textContent = `복사했습니다 (${md.length}자).`;
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

// 페이지 제목/URL은 외부 데이터라 textContent로만 넣는다
const list = document.getElementById('tabs');
for (const tab of await listTabs()) {
  const li = document.createElement('li');
  const text = document.createElement('div');
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
  text.append(t, u);
  li.append(text, btn);
  list.append(li);
}
