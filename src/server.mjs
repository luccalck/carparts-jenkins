import http from 'node:http';
import { pathToFileURL } from 'node:url';

export function createServer() {
  return http.createServer((req, res) => {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const send = (status, body) => { res.writeHead(status); res.end(JSON.stringify(body)); };
    if (req.method !== 'GET') return send(405, { error: 'Método não permitido' });
    const path = new URL(req.url, 'http://localhost').pathname;
    if (path === '/health' || path === '/') {
      return send(200, { status: 'ok', version: '1.0.0', commit: process.env.COMMIT_SHA || 'local', synthetic: true });
    }
    if (path === '/orders') {
      return send(200, { synthetic: true, orders: [
        { id: 'LAB-001', item: 'Filtro demonstrativo', quantity: 2 },
        { id: 'LAB-002', item: 'Pastilha demonstrativa', quantity: 4 }
      ] });
    }
    send(404, { error: 'Rota não encontrada' });
  });
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT || 3000);
  const server = createServer();
  server.listen(port, '0.0.0.0', () => console.log(`API de laboratório na porta ${port}`));
  for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => server.close());
}
