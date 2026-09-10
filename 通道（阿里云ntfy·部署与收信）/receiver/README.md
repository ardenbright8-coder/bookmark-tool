# receiver · 电脑端收信+回执模块（界面区就看这三行）

1. **收信**：`import { start, sendReceipt } from './receiver.js'` → `const h = start({ server: 'https://邮局域名', topic: 'bookmark-up', user: 'pc-receiver', pass: '***', since: '168h', onMessage: e => 落库刷新面板(e) })`；`e` 是 ntfy 事件 JSON（`e.message` 是内容），只喂 `event==='message'`；返回 `h.stop()` 可停。
2. **回执**：`await sendReceipt({ server, topic: 'bookmark-receipt', user, pass, title: '已收录', message: e.message })` → `{ok:true,id}` 或 `{ok:false,error}`（永不抛异常）。
3. **测试**：`npm test`（mock 服务器，不连真邮局）；断线自动重连+从最后消息 id 补收，网络异常全内部消化。
