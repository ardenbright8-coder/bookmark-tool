# bookmark_inbox · 书签收发箱（手机端）

书签工具的手机端：单页「Agent 看板」——💭待定区置顶 + 按 agent 分组（⊕无限加组/加任务），记一条推到阿里云 ntfy 邮局，电脑端收信进看板并回「已收录」。消息 JSON：`{"type":"note|bookmark|task","content","assignee","ts","attachments"}`（`attachments` 为文件名数组，可空；图只存在手机 `attachments/` 目录，不上传邮局）。`cmd` 类型收到只存不执行（云 Agent 留口）。

## 硬规矩（用户拍板，违反=返工）

- 🚨 **手机端不加项目文件夹功能；待定区和Agent分组保持现有形态**（用户原话 · 2026-09-10）。电脑端的 📁 项目文件夹不往手机搬；💭待定区置顶 + 按 agent 分组的单页形态不许改。

## 三层架构（改代码前先看）

- `lib/core/` —— **通道核心**（config / ledger 账本 / models / notifier / ntfy_client / receipt_sync 回执 / sender 发送器）。🚫 禁 import 任何 widget——这套将来整体搬去别的项目
- `lib/ui/` —— 界面：`agent_board_page.dart` 看板单页 / `agents_roster.dart` 分组清单 / `settings_dialog.dart` 服务器设置
- `android/` —— 平台层（签名/镜像仓/脱糖配置都在这，见下）

## 切服务器 / 改账号

APP 右上角齿轮 → 设置页填 ntfy 地址 + 账号密码（server 上：手机用 phone-sender，电脑用 pc-receiver）。真实值在 `..\..\通道（阿里云ntfy·部署与收信）\deploy\服务器信息（本地·不进git）.md`。

## 重出包（ASCII 构建链·照抄就成）

🚨 **为什么这么绕**：Windows 用户名是中文（`C:\Users\嘉楷\`），gradle 会把 SDK/插件路径写进 Java Properties——中文被老编码读成乱码后 CMake/ninja 直接起不来。实测两代翻车。**整条构建链必须全 ASCII**：

1. **同步源码到构建副本**（源码正本在 E 盘本夹，构建在 D 盘 ASCII 副本）：
   ```bash
   robocopy "E:\…\手机APP_收发箱_Flutter\bookmark_inbox" "D:\a-zhujiyingyong\chengxu\buildwork\bookmark_inbox" /MIR /XD .dart_tool build .git /NFL /NDL
   ```
2. **检查 `android\local.properties`**（正斜杠、无中文）：
   ```
   sdk.dir=D:/a-zhujiyingyong/chengxu/android-sdk
   flutter.sdk=D:/a-zhujiyingyong/chengxu/flutter
   ```
3. **PowerShell 里设环境再构建**（Git Bash 会把中文路径转成乱码，一律 PowerShell）：
   ```powershell
   $env:JAVA_HOME=(Split-Path (Split-Path (Get-Command java).Source))
   $env:ANDROID_SDK_ROOT='D:/a-zhujiyingyong/chengxu/android-sdk'
   $env:ANDROID_HOME=$env:ANDROID_SDK_ROOT
   $env:PUB_CACHE='D:/a-zhujiyingyong/chengxu/pub-cache'
   Set-Location 'D:/a-zhujiyingyong/chengxu/buildwork/bookmark_inbox'
   flutter build apk --release
   ```
   - 首次构建 10–20 分钟属正常；依赖下载走阿里云镜像仓（已配在 `android\settings.gradle.kts` 和 `android\build.gradle.kts`，官方仓兜底）
4. **产物**：`build\app\outputs\flutter-apk\app-release.apk`（已签名，直接能装）→ 复制到本项目 `release\`
5. **装模拟器/真机**：`adb install -r xxx.apk`；模拟器用库里 `设备模拟器（多agent共用）` 那套一键脚本

## 签名（🚨 丢了永远不能覆盖升级）

- keystore：`D:\a-zhujiyingyong\chengxu\keystores\bookmark_inbox.jks`（不在仓库）；密码在 `android\key.properties`（不在仓库）
- **离线备份两份**（U盘/云盘各一），换机器打包全靠它

## 升级路线（第一版没做的，别偷偷加）

- 📁 项目文件夹：电脑端功能，手机端明确不加（2026-09-10 拍板，见上「硬规矩」）
- 云 Agent `cmd` 指令：收到只存不执行 → 将来接执行器
- 真机后台收信：`flutter_foreground_task` 前台服务 + OriginOS 白名单（现在打开 APP 才收，够用）
- iOS：Flutter 代码 90% 复用，等 Mac + 苹果账号；上架方案未定（留白）
