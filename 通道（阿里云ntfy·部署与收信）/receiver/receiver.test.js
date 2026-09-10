/*
单测：mock 一个 ntfy HTTP 服务，不依赖真服务器。跑法：npm test（= node --test）
*/

import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { start, sendReceipt } from './receiver.js';

const wait = (ms) => new Promise(r => setTimeout(r, ms));

async function waitUntil(fn, timeoutMs = 3000, label = '条件') {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    if (fn()) return;
    await wait(20);
  }
  assert.fail(`等待超时: ${label}`);
}

/** 起一个 mock ntfy：handle(req,res,url) 自己写；返回 {server, url, close} */
async function mockServer(handle) {
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => handle(req, res, req.url, Buffer.concat(chunks).toString('utf8')));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}`;
  return {
    server, url,
    async close() {
      server.closeAllConnections?.();
      server.close();
      await once(server, 'close').catch(() => {});
    },
  };
}

const line = (obj) => JSON.stringify(obj) + '\n';

test('只把 message 事件喂给 onMessage，open/keepalive 不喂', async () => {
  const got = [];
  let handleConn;
  const connOpened = new Promise(r => { handleConn = r; });
  const s = await mockServer((req, res, url) => {
    assert.equal(url, '/bm/json');
    assert.equal(req.headers.authorization, undefined); // 没给凭证就不该带头
    res.writeHead(200, { 'Content-Type': 'application/x-ndjson' });
    res.write(line({ id: 'o1', time: 1, event: 'open' }));
    res.write(line({ id: 'k1', time: 2, event: 'keepalive' }));
    res.write(line({ id: 'm1', time: 3, event: 'message', message: '第一条', title: '标题' }));
    handleConn();
    // 挂住保持连接
  });
  try {
    const h = start({ server: s.url, topic: 'bm', onMessage: e => got.push(e) });
    await connOpened;
    await waitUntil(() => got.length === 1, 3000, '收到第一条message');
    assert.equal(got[0].id, 'm1');
    assert.equal(got[0].message, '第一条');
    assert.equal(got[0].title, '标题');
    assert.equal(got.filter(e => e.event !== 'message').length, 0);
    h.stop();
  } finally { await s.close(); }
});

test('断线后自动重连，并带 since=最后消息id 续读（断线补收）', async () => {
  const got = [];
  const seenUrls = [];
  let round = 0;
  let round2Opened;
  const round2Promise = new Promise(r => { round2Opened = r; });
  const s = await mockServer((req, res, url) => {
    seenUrls.push(url);
    round += 1;
    if (round === 1) {
      assert.equal(url, '/bm/json'); // 首连不带since
      res.writeHead(200);
      res.write(line({ id: 'mA', time: 1, event: 'message', message: 'first' }));
      setTimeout(() => res.destroy(), 30); // 模拟断线
    } else if (round === 2) {
      assert.equal(url, '/bm/json?since=mA'); // 续读命根子
      res.writeHead(200);
      res.write(line({ id: 'mB', time: 2, event: 'message', message: 'second' }));
      round2Opened();
      // 挂住
    } else {
      res.writeHead(200); // 兜底挂住，别再触发第三轮
    }
  });
  try {
    const h = start({ server: s.url, topic: 'bm', onMessage: e => got.push(e), reconnectBaseMs: 50 });
    await Promise.race([round2Promise, wait(3000).then(() => { throw new Error('第二连接没来'); })]);
    await waitUntil(() => got.length === 2, 2000, '补收第二条');
    assert.deepEqual(got.map(e => e.message), ['first', 'second']);
    h.stop();
  } finally { await s.close(); }
});

test('stop 之后不再重连', async () => {
  let conns = 0;
  const s = await mockServer((req, res) => {
    conns += 1;
    res.writeHead(200);
    res.write(line({ id: 'mA', time: 1, event: 'message', message: 'x' }));
    setTimeout(() => res.destroy(), 20);
  });
  try {
    const h = start({ server: s.url, topic: 'bm', onMessage: () => {}, reconnectBaseMs: 50 });
    await wait(150);   // 等第一次断开发生
    h.stop();
    const atStop = conns;
    await wait(400);   // 期间若在重连，50ms起跳早该连好几轮
    assert.ok(conns <= atStop + 1, `stop后不应继续重连（conns=${conns}, stop时=${atStop}）`);
  } finally { await s.close(); }
});

test('多主题数组按逗号合并订阅', async () => {
  let seenUrl;
  let opened;
  const openedP = new Promise(r => { opened = r; });
  const s = await mockServer((req, res, url) => {
    seenUrl = url;
    res.writeHead(200);
    opened();
    // 挂住
  });
  try {
    const h = start({ server: s.url, topic: ['bm-up', 'bm-receipt'], onMessage: () => {} });
    await Promise.race([openedP, wait(3000).then(() => { throw new Error('没连上'); })]);
    assert.equal(seenUrl, '/bm-up,bm-receipt/json');
    h.stop();
  } finally { await s.close(); }
});

test('start 缺参数同步抛 TypeError', async () => {
  assert.throws(() => start({ topic: 't', onMessage: () => {} }), TypeError);
  assert.throws(() => start({ server: 'http://x', onMessage: () => {} }), TypeError);
  assert.throws(() => start({ server: 'http://x', topic: 't' }), TypeError);
  assert.throws(() => start({ server: 'http://x', topic: 't', onMessage: () => {}, user: 'u' }), TypeError);
});

test('sendReceipt：POST 到 /，带 Basic 认证和 JSON body，返回 {ok,id}', async () => {
  let captured;
  const s = await mockServer((req, res, url, body) => {
    captured = { url, body: JSON.parse(body || '{}'), auth: req.headers.authorization, method: req.method };
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ id: 'r1' }));
  });
  try {
    const out = await sendReceipt({
      server: s.url, topic: 'bm-receipt', user: 'pc', pass: 'pw',
      title: '已收录', message: '电脑已收录：测试一条',
    });
    assert.deepEqual(out, { ok: true, id: 'r1' });
    assert.equal(captured.method, 'POST');
    assert.equal(captured.url, '/');
    assert.equal(captured.auth, 'Basic ' + Buffer.from('pc:pw').toString('base64'));
    assert.equal(captured.body.topic, 'bm-receipt');
    assert.equal(captured.body.title, '已收录');
    assert.equal(captured.body.message, '电脑已收录：测试一条');
  } finally { await s.close(); }
});

test('sendReceipt 无凭证不带认证头；服务异常返回 {ok:false} 而不是抛异常', async () => {
  let sawAuth;
  const s = await mockServer((req, res, url, body) => {
    sawAuth = req.headers.authorization ?? null;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ id: 'r2' }));
  });
  try {
    const out = await sendReceipt({ server: s.url, topic: 't', message: '无凭证' });
    assert.deepEqual(out, { ok: true, id: 'r2' });
    assert.equal(sawAuth, null);
  } finally { await s.close(); }

  const dead = await sendReceipt({ server: 'http://127.0.0.1:1', topic: 't', message: 'x' });
  assert.equal(dead.ok, false);
  assert.ok(typeof dead.error === 'string' && dead.error.length > 0);
});
