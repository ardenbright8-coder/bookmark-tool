# 出包（2026-09-24 趟通的整条链）：同步到 ASCII 构建副本 → 修 local.properties → 用 ASCII 的 pub 缓存重建插件路径
# → gradlew 带一次性阿里云镜像（只管插件下载源）出 release 包 → 停掉 gradle 后台（它占 3G 内存，不停模拟器起不来）。
# 用法：pwsh -File tool\build_apk.ps1 [-Install]   （-Install＝装到开着的模拟器 emulator-5640）
# 坑都写在 README「重出包」一节，这里只管照做。
param([switch]$Install)
$ErrorActionPreference = 'Stop'
$src = 'D:\A-zhujiyingyong\chengxu\bookmark-inbox\bookmark_inbox'
$work = 'D:\a-zhujiyingyong\chengxu\buildwork\bookmark_inbox'
robocopy $src $work /MIR /XD .dart_tool build .git /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy 失败 $LASTEXITCODE" }
[IO.File]::WriteAllText("$work\android\local.properties", "sdk.dir=D:/a-zhujiyingyong/chengxu/android-sdk`nflutter.sdk=D:/a-zhujiyingyong/chengxu/flutter`n", (New-Object Text.UTF8Encoding $false))
$init = Join-Path $env:TEMP 'bookmark-aliyun-once.init.gradle'
[IO.File]::WriteAllText($init, "allprojects {`n    buildscript {`n        repositories {`n            maven { url 'https://maven.aliyun.com/repository/central' }`n            maven { url 'https://maven.aliyun.com/repository/google' }`n            maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }`n        }`n    }`n}`n", (New-Object Text.UTF8Encoding $false))
$env:JAVA_HOME = Split-Path (Split-Path (Get-Command java).Source)
$env:ANDROID_SDK_ROOT = 'D:/a-zhujiyingyong/chengxu/android-sdk'
$env:ANDROID_HOME = $env:ANDROID_SDK_ROOT
$env:PUB_CACHE = 'D:/a-zhujiyingyong/chengxu/pub-cache'
Set-Location $work
& 'D:/a-zhujiyingyong/chengxu/flutter/bin/flutter.bat' pub get | Out-Null
Set-Location "$work\android"
.\gradlew.bat assembleRelease --init-script $init | Select-String 'BUILD (SUCCESSFUL|FAILED)'
$ok = $LASTEXITCODE -eq 0
.\gradlew.bat --stop | Out-Null
if (-not $ok) { throw '出包失败：去 android 目录手跑 gradlew assembleRelease --init-script 看 What went wrong' }
$apk = "$work\build\app\outputs\apk\release\app-release.apk"
Write-Output "APK: $apk"
if ($Install) { & 'D:\a-zhujiyingyong\chengxu\android-sdk\platform-tools\adb.exe' -s emulator-5640 install -r $apk }
