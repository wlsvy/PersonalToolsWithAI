// 실행: node features/clip-history/clip-history.test.mjs
import assert from 'node:assert/strict';
import { pushClip } from './clip-history.js';

assert.deepEqual(pushClip(['a', 'b'], 'b'), ['b', 'a']);
assert.deepEqual(pushClip(['1', '2', '3', '4', '5'], '6'), ['6', '1', '2', '3', '4']);
assert.deepEqual(pushClip(['# A\n', 'x'], '# A\n\n---\n\n# B'), ['# A\n\n---\n\n# B', 'x']);
console.log('ok');
