// 실행: node features/tab-list/tab-list.test.mjs
import assert from 'node:assert/strict';
import { urlList, markdownList } from './tab-list.js';

const tabs = [
  { title: 'A [b]', url: 'https://x.com/a_(b) c' },
  { title: '', url: 'https://y.com' },
];
assert.equal(urlList(tabs), 'https://x.com/a_(b) c\nhttps://y.com');
assert.equal(markdownList(tabs), '- [A \\[b\\]](https://x.com/a_%28b%29%20c)\n- [https://y.com](https://y.com)');
console.log('ok');
