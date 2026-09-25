# bookmark_inbox · 书签收发箱（手机端）

书签工具的手机端：单页「Agent 看板」——💭待定区置顶 + 按 agent 分组，**看的是电脑看板的最新一份**（电脑把整板发到阿里云 ntfy 中转站 `bookmark-board` 主题，手机拉，设定19）；每组第一格空白框记一条推到 `bookmark-up`，电脑端收信进看板并回「已收录」；长按挪组 / 删条、「可以，删掉」是发给电脑的 `type=op` 命令。消息 JSON：`{"type":"note|bookmark|task","content","assignee","ts","attachments"}`（`attachments` 为文件名数组，可空；图只存在手机 `attachments/` 目录，不上传邮局）。`cmd` 类型收到只存不执行（云 Agent 留口）。

## 硬规矩（用户拍板，违反=返工）

- 🚨 **手机端不加项目文件夹功能；待定区和Agent分组保持现有形态**（用户原话 · 2026-09-10）。电脑端的 📁 项目文件夹不往手机搬；💭待定区置顶 + 按 agent 分组的单页形态不许改。

## 三层架构（改代码前先看）

- `lib/core/` —— **通道核心**（config / ledger 账本 / models / notifier / ntfy_client / receipt_sync 回执 / sender 发送器）。🚫 禁 import 任何 widget——这套将来整体搬去别的项目
- `lib/core/board_sync.dart` —— 拉电脑整板（1 小时→1 天→7 天放宽找，断网给上一份）、记哪些自己发的进过看板（`seenKeys`）
- `lib/ui/` —— 界面：`agent_board_page.dart` 看板单页（照电脑草木皮肤；不放数数小标；分组名单以电脑为准） / `agents_roster.dart` 没拉到整板时的兜底分组 / `settings_dialog.dart` 服务器设置
- `android/` —— 平台层（签名/镜像仓/脱糖配置都在这，见下）

## 切服务器 / 改账号

APP 右上角齿轮 → 设置页填 ntfy 地址 + 账号密码（server 上：手机用 phone-sender，电脑用 pc-receiver）。真实值在 `..\..\通道（阿里云ntfy·部署与收信）\deploy\服务器信息（本地·不进git）.md`。

## 重出包（一条命令）

```powershell
pwsh -NoProfile -File tool\build_apk.ps1 -Install   # 出 release 包，-Install 顺手装到开着的模拟器
```

脚本干的事和为什么（2026-09-24 重新趟通，四个坑都在脚本里处理了）：

1. 🚨 **整条构建链必须全 ASCII**：Windows 用户名是中文（`C:\Users\嘉楷\`），gradle / CMake / ninja 碰中文路径就崩。源码同步到 `D:\a-zhujiyingyong\chengxu\buildwork\bookmark_inbox` 再构建，`android\local.properties` 每次重写成 D 盘正斜杠路径（源码里那份是中文路径，会被同步覆盖过去）。
2. 🚨 **在构建副本里用 D 盘的 pub 缓存重跑一次 `flutter pub get`**：源码里的 `.flutter-plugins-dependencies` 记着 `C:\Users\嘉楷\…\Pub\Cache` 的插件路径，jni 插件的 C++ 构建会 chdir 失败。
3. 🚨 **插件自己的下载源要走阿里云**：image_picker 等插件要 Kotlin 插件，默认去 `repo.maven.apache.org`，直连握手被掐。主工程配了镜像不管插件；全局 `~\.gradle\init.d` 那份镜像脚本被人关了（`.off`），别动它——脚本临时生成一份**只管 buildscript** 的 init 脚本传给这一次构建（管 project 仓库会跟 settings 冲突报 FAIL_ON_PROJECT_REPOS）。所以不用 `flutter build apk`，直接 `gradlew assembleRelease --init-script`。
4. 🚨 **出完包 `gradlew --stop`**：gradle 后台进程占 3G 内存，不停的话模拟器起不来（可提交内存不够）。

产物 `build\app\outputs\apk\release\app-release.apk`（已签名）→ 复制到本项目 `release\`。

**模拟器**：公用那台 `GetawayTest_API34` 现在起不来（Windows 把 5532-5631、6311-6410 两段端口保留了，模拟器默认 5554/5555 和蓝牙 6402 都在里面；另外它自己会解析回中文长路径）。测本 APP 用 D 盘 ASCII 那套：见库里 `设备模拟器（多agent共用·测应用）\01_安卓（Google Emulator）\各agent怎么用\AI必读（30秒）.md` 坑表最后一行。

## 签名（🚨 丢了永远不能覆盖升级）

- keystore：`D:\a-zhujiyingyong\chengxu\keystores\bookmark_inbox.jks`（不在仓库）；密码在 `android\key.properties`（不在仓库）
- **离线备份两份**（U盘/云盘各一），换机器打包全靠它

## 升级路线（第一版没做的，别偷偷加）

- 📁 项目文件夹：电脑端功能，手机端明确不加（2026-09-10 拍板，见上「硬规矩」）
- 云 Agent `cmd` 指令：收到只存不执行 → 将来接执行器
- 真机后台收信：`flutter_foreground_task` 前台服务 + OriginOS 白名单（现在打开 APP 才收，够用）
- iOS：Flutter 代码 90% 复用，等 Mac + 苹果账号；上架方案未定（留白）
