import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from '../src/server.mjs';

async function request(path, options) {
  const server = createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}${path}`, options);
    return { status: response.status, body: await response.json() };
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}
describe('API Carparts', () => {
test('health informa disponibilidade e versão', async () => {
  const response = await request('/health');
  assert.equal(response.status, 200);
  assert.equal(response.body.status, 'ok');
  assert.equal(response.body.version, '1.0.0');
});
test('pedidos são exclusivamente dados sintéticos', async () => {
  const response = await request('/orders');
  assert.equal(response.status, 200);
  assert.equal(response.body.synthetic, true);
  assert.equal(response.body.orders.length, 2);
});
test('rota inexistente retorna 404', async () => {
  assert.equal((await request('/inexistente')).status, 404);
});
test('POST não autorizado retorna 405', async () => {
  assert.equal((await request('/orders', { method: 'POST' })).status, 405);
});
});
