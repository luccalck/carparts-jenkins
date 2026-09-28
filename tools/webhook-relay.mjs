import http from 'node:http';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export function createRelay({ secret, repository, upstream = 'http://127.0.0.1:8082/github-webhook/' }) {
  if (!secret || !repository) throw new Error('Defina WEBHOOK_SECRET e GITHUB_REPOSITORY');
  return http.createServer(async (req, res) => {
    const send = (status, text) => { res.writeHead(status, { 'Content-Type': 'text/plain' }); res.end(text); };
    if (req.method !== 'POST' || req.url !== '/github-webhook/') return send(404, 'Not found');
    if (req.headers['content-type']?.split(';')[0] !== 'application/json') return send(415, 'JSON required');
    const chunks = []; let length = 0;
    try {
      for await (const chunk of req) {
        length += chunk.length;
        if (length > 1048576) return send(413, 'Too large');
        chunks.push(chunk);
      }
      const body = Buffer.concat(chunks);
      const signature = req.headers['x-hub-signature-256'] || '';
      const expected = `sha256=${createHmac('sha256', secret).update(body).digest('hex')}`;
      if (signature.length !== expected.length || !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return send(403, 'Signature rejected');
      const event = req.headers['x-github-event'];
      if (!['ping', 'push', 'pull_request'].includes(event)) return send(202, 'Event ignored');
      const data = JSON.parse(body);
      if (data.repository?.full_name !== repository) return send(403, 'Repository rejected');
      const response = await fetch(upstream, { method: 'POST', body, signal: AbortSignal.timeout(10000), headers: {
        'Content-Type': 'application/json', 'X-GitHub-Event': event,
        'X-GitHub-Delivery': req.headers['x-github-delivery'] || ''
      } });
      send(response.status, response.ok ? 'Webhook accepted' : 'Upstream rejected');
    } catch { send(502, 'Webhook unavailable'); }
  });
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const relay = createRelay({ secret: process.env.WEBHOOK_SECRET, repository: process.env.GITHUB_REPOSITORY });
  relay.requestTimeout = 15000;
  relay.listen(8083, '127.0.0.1', () => console.log('Relay local em 127.0.0.1:8083. Nenhuma interface Jenkins exposta.'));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => relay.close());
}
