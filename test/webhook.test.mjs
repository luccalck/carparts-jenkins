import http from 'node:http';
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { createRelay } from '../tools/webhook-relay.mjs';
describe('Segurança do webhook', () => {
test('relay aceita assinatura válida e bloqueia assinatura incorreta e interface', async () => {
  const secret = 'synthetic-unit-test-secret';
  let forwarded = 0;
  const upstream = http.createServer((req, res) => { forwarded++; res.end('OK'); });
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  const relay = createRelay({ secret, repository: 'lab/repo', upstream: `http://127.0.0.1:${upstream.address().port}/github-webhook/` });
  await new Promise(resolve => relay.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${relay.address().port}`;
  const body = JSON.stringify({ repository: { full_name: 'lab/repo' } });
  const headers = { 'Content-Type': 'application/json', 'X-GitHub-Event': 'push', 'X-Hub-Signature-256': `sha256=${createHmac('sha256', secret).update(body).digest('hex')}` };
  try {
    assert.equal((await fetch(`${url}/github-webhook/`, { method: 'POST', headers, body })).status, 200);
    assert.equal((await fetch(`${url}/github-webhook/`, { method: 'POST', headers: { ...headers, 'X-Hub-Signature-256': 'sha256=invalid' }, body })).status, 403);
    assert.equal((await fetch(`${url}/manage`)).status, 404);
    assert.equal(forwarded, 1);
  } finally {
    await Promise.all([new Promise(resolve => relay.close(resolve)), new Promise(resolve => upstream.close(resolve))]);
  }
});
});
