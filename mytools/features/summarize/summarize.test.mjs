// 실행: node features/summarize/summarize.test.mjs
import assert from 'node:assert/strict';
import { countWords, sourceLink, stripCitations, stripLinkTitles } from './summarize.js';

assert.equal(
  stripCitations('oases[1](#ref-CR1),[2](https://x.org/a#ref-CR2), rare[6](#ref-CR6)–[8](#ref-CR8). Next'),
  'oases, rare. Next',
);
assert.equal(stripCitations('fact[\\[3\\]](https://w.org/a#cite_note-3) x'), 'fact x');
assert.equal(stripCitations('see [Fig. 2](https://x.org/f2)'), 'see [Fig. 2](https://x.org/f2)');

assert.equal(
  stripLinkTitles('humans[1](https://x.org/a#ref-CR1 "Proops, L. (2012). \\"Horses\\".").'),
  'humans[1](https://x.org/a#ref-CR1).',
);
assert.equal(stripLinkTitles('[a](https://x.org/f\\(1\\) "t")'), '[a](https://x.org/f\\(1\\))');
assert.equal(stripLinkTitles('[a](https://x.org) "not a title"'), '[a](https://x.org) "not a title"');
assert.equal(countWords('  one two\n\nthree '), 3);
assert.equal(sourceLink('A [b] c', 'https://x.org/f(1) a'), '[A \\[b\\] c](https://x.org/f%281%29%20a)');
console.log('ok');
