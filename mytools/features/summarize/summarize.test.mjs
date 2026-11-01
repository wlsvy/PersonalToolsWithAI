// 실행: node features/summarize/summarize.test.mjs
import assert from 'node:assert/strict';
import { countWords, stripLinkTitles } from './summarize.js';

assert.equal(
  stripLinkTitles('humans[1](https://x.org/a#ref-CR1 "Proops, L. (2012). \\"Horses\\".").'),
  'humans[1](https://x.org/a#ref-CR1).',
);
assert.equal(stripLinkTitles('[a](https://x.org/f\\(1\\) "t")'), '[a](https://x.org/f\\(1\\))');
assert.equal(stripLinkTitles('[a](https://x.org) "not a title"'), '[a](https://x.org) "not a title"');
assert.equal(countWords('  one two\n\nthree '), 3);
console.log('ok');
