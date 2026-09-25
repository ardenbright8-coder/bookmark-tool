---
这是啥: 设定15「派活给 AI」的规则正文——捆一捆、启动 Agent、AI 用命令领活、在干标记、用户说可以才删
谁看: 要动捆、领活命令、启动 Agent 的 AI
什么时候用: 改 store.ts 的捆/领活、cli-server.ts 的 next/done/release、bookmark.js 的捆头/在干之前
版本: 2026-09-24
状态: 已实现（2026-09-24 当天改到第四版：启动 Agent 开桌面快捷方式，命令窗口贴进新窗口，Codex、Hermes 先 Ctrl+N 新开对话再贴）
---

# 设定 15 · 派活给AI（捆一捆·AI领活·在干·用户说可以才删） —— 设计规则

2026-09-24 立。

## 三条铁律

1. 🚨 **看板不往 AI 窗口里塞活，是 AI 自己来领。** 看板认不出开着的窗口，所以窗口名由看板在「启动 Agent」那一刻起（Claude-3），之后领活、干完都报这个名。
2. 🚨 **一次只领一条。** 一捆交给一个窗口，但 AI 注意力有限，一条干完再领下一条，不一次把整捆塞给它。
3. 🚨 **用户亲口说「可以」才删。** AI 干完先把做了啥、怎么验讲给用户，用户说可以，再把他的原话放进 `done --ok`；不带原话命令不收。回车永远是用户自己按。

## 该长什么样

**捆一捆**（只在 agent 组里）
- 按住一条拖到另一条的**正中间**（上下各留 30% 给插缝）松手＝捆上，挪到那一捆的最后；学手机桌面把图标叠一起建文件夹
- 捆外面套一个淡虚线框，框顶一行＝六个点＋名字（第一条开头 16 个字）＋谁在干
- 往捆里加：拖到框里任意一条正中间，或插进框里两条之间；拆：拖到框外不挨着框的缝里，或捆头六个点「拆开这一捆」
- 只能捆同一组；改派到别的组自动离捆；用户挪来挪去后只剩一条的捆自动散（AI 干完删条目不散，最后一条还要能按捆号领）

**启动 Agent**
- 单条六个点、捆头六个点都有「启动 Agent · 带编程 / 普通」：单条领这一条，捆头领整捆
- 点了：看板起窗口名（组名去空格-递增号，号存 `launch-seq.json`），把一句
  `领看板的活：node "<仓库>/scripts/bookmark-cli.mjs" next <捆号或条目id> --by Claude-3 [--coding]`
  放进剪贴板，**再打开这个组对应的桌面快捷方式**——就是用户平时双击的那个，启动参数、账号都跟着快捷方式走：
  Claude → `Claude Code 一`、ChatGPT → `Codex`、Pi Agent → `Pi 编程智能体`、Antigravity → `Antigravity 反重力CLI`（命令窗口；它开窗先登录，所以等 12 秒再贴，别的等 4 秒）、Hermes → `Hermes`
- **Claude、Pi（每点一次开一个新命令窗口）：看板等新窗口启动好，替用户按一次 Ctrl+V**，提示「启动句已贴进 Claude-3 窗口，没按回车：你看一眼再按回车」（用户选的做法 2）
  - 怎么认新窗口：开窗前记下已有的全部窗口，之后跑到最前面、又不在这份名单里的才算；出来后再等 4 秒让它启动好，那时它还在最前面才贴
  - 新窗口 15 秒没到最前面、等的时候用户点了别的窗口：不贴，提示「…没替你贴：点一下 Claude-3 窗口，Ctrl+V 再回车」
  - 按之前再把启动句放一次剪贴板（等的几秒里用户可能复制了别的）
- **Codex、Hermes（桌面程序，开着的话点快捷方式只是把旧窗口切到前面）：看板认出这个程序跑到最前面、启动好，替用户按 Ctrl+N 新开一个对话，再按 Ctrl+V**，提示「等它启动好，看板替你新开一个对话、把启动句贴进去」（2026-09-24 第四版）
  - 怎么认：按「最前面那个窗口是哪个程序」认，不按新旧窗口认——Codex 桌面版的程序文件叫 `ChatGPT.exe`（不是 codex.exe），Hermes 是 `Hermes.exe`
  - 要它**连续在最前面 5 秒**才算启动好：启动画面、黑框一闪把它挤下去又回来，从回来那刻重新等；30 秒都没稳住就不贴
  - 按 Ctrl+N 后等 1.5 秒新对话出来，那时还是它在最前面才贴；中途用户点了别的窗口就停手
  - 启动句在按 Ctrl+N 时就放进剪贴板，贴的时候剪贴板没被换掉就不再写：刚写剪贴板那一刻，剪贴板工具（这台机器上有 PasteBar）会去读、占住一小会儿，紧跟着 Ctrl+V 会贴空（2026-09-24 实测）
- 🚨 **绝不按回车**：看板只按 Ctrl+V（桌面程序多一个 Ctrl+N 新开对话），回车永远用户自己按
- 用户自己加的组、桌面上没这个快捷方式、打开失败：不开窗，退回「开一个新的 X 窗口，Ctrl+V 再回车」，并说明为什么没开

**AI 领活**（所有 AI 同一套，规矩由 `next` 自己吐出来，不用事先读别的文件）
- `next`：给这一捆里下一条没人领的（同一个窗口没干完再敲还是那条），看板上标「🔄 Claude-3 在干」，别的窗口领不走；`--coding` 就把 `带编程.md` 拼在前面
- `done <id> --by 窗口名 --ok "用户原话"`：只有领它的窗口能删；删完敲 `next` 领下一条
- `release <id> --by 窗口名`：放回去；看板上六个点也有「放回去」（窗口半路关了用）
- 一捆领完：`next` 说「没有可领的了，还有谁在干」

## 代码落在哪

| 干什么 | 在哪 |
|---|---|
| 数据字段 `bundleId` / `claimedBy` / `claimedAt` | `store.ts` → `BookmarkRecord`，旧库读入补 null |
| 捆、挪完定捆、改派离捆、散单条捆 | `store.ts` → `bundleWith` / `settleBundleAfterMove` / `setAssignee` / `dissolveLoneBundles` / `unbundle` |
| 领、删、放回 | `store.ts` → `claimNext` / `done` / `release` |
| 命令参数、服务端、统一领活说明 | `cli-server.ts` → `parseClaimArgs` / `handleClaimRequest` / `formatClaimMessage`；`scripts/bookmark-cli.mjs` |
| 启动句、窗口名 | `panel-window.ts` → IPC `bookmark:launch-line`、`nextWindowLabel`、`bookmarkCliScriptPath` |
| 哪个组开哪个快捷方式、打开 | `launch.ts` → `agentShortcutFor`（纯函数）；`panel-window.ts` → `openAgentShortcut`（自测和验证脚本带隔离数据夹 `AGENT_PET_HUB_HOME`，只报会怎么做、不真开——别改回只看「常驻」，验证脚本也常驻，2026-09-24 误开过 11 个真 Claude 窗口；设了 `BOOKMARK_AGENT_SHORTCUT_DIR` 才从那个夹真开，给真机验证用） |
| 认新窗口、等启动好、贴 | `launch.ts` → `pasteIntoNewWindow`（命令窗口）/ `pasteIntoAppWindow`（桌面程序，按程序名认、先 Ctrl+N）——判断逻辑，Windows 能力由外面传进来；`agentShortcutFor` 里的 `app` 是桌面程序的程序文件名；`panel-window.ts` → `loadLaunchWin32`（EnumWindows / GetForegroundWindow / 查窗口是哪个程序 / keybd_event）、`pasteLaunchLine`（结果发 `bookmark:launch-pasted`） |
| 捆头、框、在干标记、正中间判定 | `renderer\bookmark.js` → `bmBuildBundleHead` / `bmFillTaskList` / `bmBindDrag`（`bundleable`）/ `bmBuildTask` |

### 硬约束

1. 🚨 **领活说明只在 `formatClaimMessage` 写一次**，Claude、Codex、Pi、Hermes 看到的一个字不差；要改规矩改这里，别在别处另写一份。
2. 🚨 **`done` 两层把关**：命令服务先拦空 `--ok`，`store.done` 再拦一次、并核对是不是本窗口领的。
3. 命令里的脚本路径用正斜杠，哪种终端都能直接粘。
4. 捆的顺序就是数组顺序：一捆永远挨着；「夹在同一捆两条中间＝进捆；本来在捆里、挪到捆边上＝留下；别的＝离开」。

## 拿什么验收

```
npm run build && node --test dist/testkit/tests/bookmark-bundle.test.js dist/testkit/tests/bookmark-cli.test.js dist/testkit/tests/bookmark-launch.test.js
node scripts/verify-bookmark-copy.mjs
node scripts/verify-bookmark-launch-paste.mjs   # 真机：会弹一个命令窗口和一个假 Codex 小窗口，跑的半分钟别碰键盘鼠标
```

单测 7 项管捆和领活规则，命令单测管参数、服务端、统一说明，`bookmark-launch` 管哪个组开哪个快捷方式、什么时候贴什么时候不贴（新窗口正常出来 / 用户点了旧窗口 / 等时切走 / 没有前台窗口）；界面验证 ⑤b 启动 Agent 提示开了「Claude Code 一」、⑧～⑩ 真拖到正中间捆、真敲命令领活（看板出在干、别的窗口领到下一条、不带原话 done 不收、带了才删）、六个点放回去。2026-09-24 全绿，连跑三轮一致。`verify-bookmark-launch-paste` 用假快捷方式指向假 AI 程序（`scripts/bookmark-fake-agent.ps1`，记下收到的字和有没有回车），真开窗、真贴：收到的字＝启动句一字不差、没有回车。⑤～⑨ 桌面程序：把 powershell.exe 复制改名 `ChatGPT.exe` 冒充 Codex，跑 `scripts/bookmark-fake-desktop-agent.ps1`（带输入框的小窗口，记下 Ctrl+N、收到的字、回车）：先收到 Ctrl+N 再收到启动句、没有回车、看板提示已贴进。2026-09-24 连跑三轮全绿；当天也拿真 Codex、真 Hermes 各试了一次，都是新开对话、启动句在输入框里没发出去。

## 还没做的

- 以后让 AI 帮忙整理当天条目、自动捆好：AI 只许捆和拆，不许改字、不许删条（用户说过，还没排期）。
