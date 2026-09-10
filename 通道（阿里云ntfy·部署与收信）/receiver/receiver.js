/*
---
这是啥: 电脑端收信+回执模块——连ntfy收手机发来的记录（吐标准JSON事件），发「已收录」回执
谁看: 书签台界面区（桌宠src\bookmark\）的接线agent；修消息链路的agent
什么时候用: 电脑端要收手机消息/发回执时；链路排障先跑同夹单测
改之前必看: 一切网络异常必须内部消化（指数退避重连），禁止抛给调用方；"最后消息id作since续读"是断线补收的命根子，别动
*/

import http from 'node:http';
import https from 'node:https';
import { StringDecoder } from 'node:string_decoder';

// 注：不用 readline——实测（2026-09-09）挂上 readline 后，服务端 RST 时流的 error 事件会丢失变成未捕获异常，
// 自己按 \n 切分行为完全可控。
function pipeLines(res, onLine, onEnd, onError) {
  const decoder = new StringDecoder('utf8');
  let buf = '';
  res.on('data', (chunk) => {
    buf += decoder.write(chunk);
    let idx;
    while ((idx = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, idx);
      buf = buf.slice(idx + 1);
      if (line.trim()) onLine(line);
    }
  });
  res.on('end', () => {
    const tail = (buf + decoder.end()).trim();
    if (tail) onLine(tail);
    onEnd();
  });
  res.on('error', onError);
}

const MAX_BACKOFF_MS = 60_000;

function pickHttpModule(server) {
  return server.startsWith('https:') ? https : http;
}

/**
 * 订阅 ntfy 主题，收到消息逐条喂给 onMessage。
 * @param {object} opts
 * @param {string} opts.server        邮局地址，不带尾斜杠（如 https://ntfy.example.com）
 * @param {string|string[]} opts.topic 主题，字符串或数组（数组按逗号合并订阅）
 * @param {string} [opts.user]        账号（与 pass 成对给）
 * @param {string} [opts.pass]        密码
 * @param {function} opts.onMessage   收到消息回调，参数是 ntfy 的 JSON 事件对象（只喂 event==='message'）
 * @param {string} [opts.since]       首次连接的补收起点（如 '168h' 或某消息id）；缺省只收新消息
 * @param {function} [opts.log]       日志注入（默认 console.error；测试可换）
 * @param {number} [opts.reconnectBaseMs] 重连基础退避毫秒（默认1000，测试用小值）
 * @returns {{stop: function}} stop() 停止订阅并不再重连
 */
export function start(opts) {
  const { server, topic, onMessage } = opts ?? {};
  if (typeof server !== 'string' || !server) throw new TypeError('start: 缺 server');
  if (!topic || (Array.isArray(topic) && topic.length === 0)) throw new TypeError('start: 缺 topic');
  if (typeof onMessage !== 'function') throw new TypeError('start: 缺 onMessage');
  const hasUser = opts.user != null, hasPass = opts.pass != null;
  if (hasUser !== hasPass) throw new TypeError('start: user/pass 必须成对给');

  const log = opts.log ?? ((...a) => console.error('[receiver]', ...a));
  const baseMs = typeof opts.reconnectBaseMs === 'number' ? opts.reconnectBaseMs : 1000;
  const topics = (Array.isArray(topic) ? topic : [topic]).map(t => String(t).trim()).filter(Boolean).join(',');
  const authHeader = hasUser
    ? 'Basic ' + Buffer.from(`${opts.user}:${opts.pass}`).toString('base64')
    : undefined;

  let stopped = false;
  let lastId = undefined;        // 断线补收的命根子：重连时从最后一条消息之后续读
  let currentReq = undefined;
  let reconnectTimer = undefined;
  let attempt = 0;

  function scheduleReconnect(reason) {
    if (stopped) return;
    const delay = Math.min(MAX_BACKOFF_MS, baseMs * 2 ** attempt) + Math.floor(Math.random() * 250);
    attempt += 1;
    log(`断开（${reason}），${delay}ms 后第 ${attempt} 次重连`);
    reconnectTimer = setTimeout(connect, delay);
  }

  function connect() {
    if (stopped) return;
    const url = `${server}/${topics}/json${lastId ? `?since=${encodeURIComponent(lastId)}` : (opts.since ? `?since=${encodeURIComponent(opts.since)}` : '')}`;
    try {
      const req = pickHttpModule(server).get(url, { headers: authHeader ? { Authorization: authHeader } : {} }, (res) => {
        if (res.statusCode !== 200) {
          res.resume();
          scheduleReconnect(`HTTP ${res.statusCode}`);
          return;
        }
        attempt = 0; // 建立成功，退避归零
        pipeLines(
          res,
          (line) => {
            if (stopped) return;
            let evt;
            try { evt = JSON.parse(line); } catch { log(`坏行跳过: ${line.slice(0, 80)}`); return; }
            if (evt && evt.id) lastId = evt.id;          // open/message 都推进游标
            if (evt && evt.event === 'message') {
              try { onMessage(evt); } catch (e) { log(`onMessage 回调抛错（已吞掉）: ${e?.message ?? e}`); }
            }
          },
          () => scheduleReconnect('流结束'),
          (e) => scheduleReconnect(e?.code ?? '响应错误'),
        );
      });
      currentReq = req;
      req.on('error', (e) => scheduleReconnect(e?.code ?? '请求错误'));
    } catch (e) {
      scheduleReconnect(e?.message ?? '连接异常');
    }
  }

  connect();

  return {
    stop() {
      stopped = true;
      if (reconnectTimer) clearTimeout(reconnectTimer);
      if (currentReq) currentReq.destroy();
    },
  };
}

/**
 * 发「已收录」回执（绝不 throw——结果用返回值表达，调用方自行记日志）。
 * @param {object} opts { server, topic, user?, pass?, title?, message, tags? }
 * @returns {Promise<{ok: true, id: string} | {ok: false, error: string}>}
 */
export async function sendReceipt(opts) {
  const { server, topic, message } = opts ?? {};
  if (typeof server !== 'string' || !server || !topic || typeof message !== 'string') {
    return { ok: false, error: 'sendReceipt: 缺 server/topic/message' };
  }
  const headers = { 'Content-Type': 'application/json' };
  if (opts.user != null && opts.pass != null) {
    headers.Authorization = 'Basic ' + Buffer.from(`${opts.user}:${opts.pass}`).toString('base64');
  }
  try {
    const res = await fetch(`${server}/`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ topic, title: opts.title, message, tags: opts.tags }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) return { ok: false, error: `HTTP ${res.statusCode ?? res.status}` };
    const body = await res.json().catch(() => ({}));
    return body?.id ? { ok: true, id: body.id } : { ok: false, error: '响应缺 id' };
  } catch (e) {
    return { ok: false, error: e?.message ?? String(e) };
  }
}
