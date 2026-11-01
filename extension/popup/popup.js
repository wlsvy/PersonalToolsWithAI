import { toggleGrayscale } from '../features/grayscale/grayscale.js';
import { listTabs } from '../features/tab-list/tab-list.js';

const status = document.getElementById('status');

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
for (const { title, url } of await listTabs()) {
  const li = document.createElement('li');
  const t = document.createElement('div');
  const u = document.createElement('div');
  t.className = 'title';
  u.className = 'url';
  t.textContent = title;
  u.textContent = url;
  li.append(t, u);
  list.append(li);
}
