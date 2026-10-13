---
name: remote-tv-adblock
slug: remote-tv-adblock
displayName: 远程关闭电视广告
version: "1.1.0"
summary: 通过 ADB 远程优化安卓电视/盒子：去广告、装第三方桌面并保活、绕过广电合规安装拦截、远程关机、画质参数指引。强制先核实机型固件与权限边界再动手，只执行实测可用命令，全程可逆。
license: MIT-0
description: "通过 ADB 远程优化安卓电视与电视盒子——去广告、装第三方桌面并保活、绕过广电合规安装拦截、远程关机、画质参数指引。当用户要求「优化小米电视/电视去广告/电视开机提速/装当贝桌面/电视卡顿/换电视桌面/电视装不了应用/提示违规功能禁止安装/按HOME键回原生桌面/桌面被换回来/电视关机/电视画面偏蓝」或提供电视 IP 要求远程操作电视时使用。核心方法论：不同年份机型包名与权限机制完全不同，照抄网上教程会静默失败或黑屏；只执行实测可用命令（老机型 pm disable-user 会被权限拒，用 am force-stop 替代）；每个动作前后做健康验证与状态备份。含桌面竞争解决（第三方桌面 vs 特权原生桌面的保活策略）、广电拦截绕过（adb 直装）、画质参数边界（adb 只能改亮度）。★沉淀自 MiTV4-ANSM0(Android 6.0.1) 实战：AI 生成的方案 11 个包名 5 个是错的、核心命令权限被拒完全跑不了、照顺序执行会黑屏。触发词：优化电视、电视去广告、去广告、开电视ADB、装当贝桌面、换桌面、电视装不了应用、安装失败、违规功能禁止安装、电视提速、电视优化、ADB电视、远程改电视、盒子去广告、电视广告多、桌面被换回、保活桌面、远程关电视、电视画面偏蓝。"
agent_created: true
---

# 远程关闭电视广告

> 由来：2026-10-13 一台小米电视 MiTV4-ANSM0 实操。二手教程（AI 生成）给的方案 **11 个包名 5 个是错的**、**核心命令权限被拒完全跑不了**、**照顺序执行会黑屏**。改用实测路径后完成，并靠多方评审发现「重启即恢复」这条结论本身是错的。

## 铁律

**1. 不照抄任何现成方案，先核实再执行。** AI 生成的电视优化教程几乎都是给新版 PatchWall 写的，老机型上包名全不一样。且 `pm disable-user` 会**静默失败——不报错 ≠ 生效**。

**2. 动手前必须核实三件事**（决定后续所有命令选型）：
```bash
adb shell getprop ro.build.version.release     # Android 版本
adb shell getprop ro.build.version.incremental  # 固件版本
adb shell pm list packages                      # 真实存在的包
```
Android 6.0（SDK 23）与 Android 9+ 权限模型完全不同，命令集不通用。

**3. 桌面永远不动。** 禁用唯一桌面 = 直接黑屏开不了机。除非已装好第三方桌面并验证可用。

**4. 每次改完必验健康状态**（见「验证闸门」）。

**5. 只做可逆操作。** `force-stop` / `am start` 可逆；`disable-user` / `uninstall` / `remount` 可能永久改动，默认不做。

---

## 快速开始

```bash
bash scripts/tv_adb.sh probe    <IP>          # ① 体检（首次必跑）：机型/权限边界/桌面/内存
bash scripts/tv_adb.sh deadbiz  <IP>          # ② 去广告
bash scripts/tv_adb.sh install  <IP> <apk>    # ③ 装 APK（绕过广电拦截）
bash scripts/tv_adb.sh launcher <IP>          # ④ 桌面情况 + 特权分析
bash scripts/tv_adb.sh keep     <IP>          # ⑤ 保活第三方桌面
bash scripts/tv_adb.sh status   <IP>          # 状态查看
bash scripts/tv_adb.sh brightness <IP> [0-255] # 亮度
bash scripts/tv_adb.sh power    <IP>          # 关机
bash scripts/tv_adb.sh restore  <IP>          # 恢复被停用的服务
```

## 标准流程（七步，不得跳步）

### 第 1 步 · 装 adb

brew 常因 GitHub 网络受限失败。**直接下官方 zip**：
```bash
mkdir -p ~/tools/android && cd ~/tools/android
curl -L -o pt.zip "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
unzip -q pt.zip
export PATH="$HOME/tools/android/platform-tools:$PATH"
adb version
```

### 第 2 步 · 定位电视（优先 mDNS，别全网段扫）

```bash
dns-sd -B _airplay._tcp local                   # 2 秒出结果
dns-sd -L "<设备名>" _airplay._tcp local         # 取详情（含 MAC）
```
拿到 MAC 后 `arp -a | grep <MAC 片段>` 反查 IP。
**换了网络后 IP 会变，先扫网段（ping 循环）再 arp 匹配 MAC。**

### 第 3 步 · 确认电视侧 ADB 已开

```bash
nc -z -G 2 <IP> 5555
```
- `Connection refused` → 电视在线但 ADB 没开（**最常见**，不是 IP 错）
- `succeeded` → 已开

**开 ADB（用户操作，不可代办）**：设置 → 关于 → 产品型号 → 确认键**连按 7 次** → 设置 → 账号与安全 → ADB 调试 → 开。

```bash
adb connect <IP>:5555
for i in $(seq 1 40); do
  [ "$(adb -s <IP>:5555 get-state 2>/dev/null)" = "device" ] && break
  sleep 5
done
```
授权通常需 30 秒。**必须提前告知用户到电视前点「始终允许」**。

### 第 4 步 · 备份现状（必做）

```bash
BK=~/tv-opt/backup_$(date +%Y%m%d_%H%M%S); mkdir -p "$BK"
adb shell pm list packages -d > "$BK/disabled_before.txt"
adb shell pm list packages -s > "$BK/system_pkgs_before.txt"
adb shell getprop              > "$BK/getprop.txt"
```

### 第 5 步 · 探测权限边界（决定用什么命令）

| 命令 | 预期结果 |
|---|---|
| `pm disable-user --user 0 <pkg>` | 多数机型 SecurityException |
| `pm hide <pkg>` | 多数机型 SecurityException |
| `which su` | 无 root 则 not found |
| `mount \| grep system` | 通常 `ro`（只读） |
| **`am force-stop <pkg>`** | **几乎必然成功 ← 唯一可用手段** |

**典型报错含义**：
```
SecurityException: Permission Denial: attempt to change component state from uid=2000
```
→ 该固件把 `MANAGE_USERS` / `CHANGE_COMPONENT_ENABLED_STATE` 从 shell 移除。**对系统包和普通第三方包全部被拒**。不要重试、不要找 root，直接转 force-stop。

### 第 6 步 · 执行

用 `scripts/tv_adb.sh`，每个子命令都做包名存在性校验（杜绝静默失败）。

### 第 7 步 · 验证闸门（三项全过才算完成）

```bash
adb shell "dumpsys window windows" | grep mCurrentFocus          # 桌面是否正常
adb shell "dumpsys package com.mitv.tvhome" | grep -oE "stopped=(true|false)"
adb shell "logcat -d -b crash -t 30" | grep -ci FATAL            # 必须为 0
adb shell pm list packages -d                                     # 与备份对比
```
另需实测唤醒后桌面可回：
```bash
adb shell input keyevent KEYCODE_WAKEUP; adb shell input keyevent KEYCODE_HOME
sleep 4; adb shell "dumpsys window windows" | grep mCurrentFocus
```
待机时焦点在 `com.mitv.screensaver` 属正常。

---

## 关键机制（★ 最容易搞错，必读）

### force-stop ≠ 禁用，且重启后大概率自动恢复

`am force-stop` = **杀进程 + 置 `stopped="true"` 标志**。这个标志**并非一律跨重启保留**——

| 包类型 | 重启后 | 原因 |
|---|---|---|
| **提供 Binder 服务的包**（广告服务、统计、推送） | ❌ 自动复活 | system_server 启动时 bind 它们，**绑定动作即清 stopped** |
| **不被系统依赖的包**（游戏中心、音乐） | ✅ 保持停止 | 无 bind 方 |

> **结论：force-stop 是「会话内」的临时抑制，不是持久禁用。要持久必须配定时任务。**

⚠️ **恢复方式永远是「启动该包任一组件」**（`am startservice` 或电视上手动打开），**不是「重启」**。

### 包名跨机型不通用

| 网上常见写法 | 实际（2016 老机型） |
|---|---|
| `com.mitv.tvhome.atv` | `com.mitv.tvhome` |
| `com.xiaomi.mitv.advertise` | 不存在 |
| `com.xiaomi.mibox.gamecenter` | `com.xiaomi.gamecenter.sdk.service.mibox` |
| `com.miui.systemAdSolution` | ✅ 通用 |

**永远以 `pm list packages` 实测为准。**

### 老电视 `ps -A` 不可用（★ 重要）

```bash
$ adb shell "ps -A" | head
USER  PID  PPID  VSIZE  RSS  WCHAN  PC  NAME     ← 只有表头，没有任何进程
```
老 Android 的 shell 权限限制。`ps -A | grep -c <包名>` **恒为 0**，用它判断进程存活会全部误判。

✅ **必须改用**：`adb shell "dumpsys activity processes" | grep -c <包名>`

---

## 桌面管理与保活（★ 常见需求）

### 为什么设不了系统默认桌面

实测的三层封锁：

| 手段 | 结果 |
|---|---|
| `pm set-home-activity` | **Android 6.0 无此命令**（Oreo 才加） |
| `pm clear-package-preferred-activities` | 也无此命令 |
| `pm disable/hide` 原生桌面 | SecurityException（缺 MANAGE_USERS） |
| 写 `preferred-activities.xml` | 无写权限（需 root） |

**根因**：原生桌面是 **PRIVILEGED 特权应用**（`privateFlags=[PRIVILEGED]`），即使装在 `/data/app` 也保留系统身份。Android 的 IntentResolver 中**特权应用永远优先**。

### ✅ 正确解法：保活，而不是压制

**实测数据**（MiTV4-ANSM0）：

| 场景 | 耗时 | 结果 |
|---|---|---|
| 第三方桌面**进程存活** | 0.15-0.26 秒 | ✅ 按 HOME 直接进 |
| 第三方桌面**被内存回收** | 0.3-2.2 秒 | ❌ **先落原生桌面再切** |

**关键认知**：第三方桌面（如当贝）自带 `HomeKeyEventCatchService`，**进程活着时能直接接住 HOME 键**。

> ❌ 错误做法：`force-stop` 原生桌面
> 实测这会让系统重新 bind 它，**反而拖慢 HOME 响应**。
>
> ✅ 正确做法：**保住第三方桌面进程存活**（`tv_guard.sh check`）

### 进程为什么会被回收

1.6GB 老机器上，视频类 App 动辄占 200MB+，第三方桌面被挤出内存。

```bash
adb shell "dumpsys meminfo" | sed -n '/Total PSS by process/,+14p'   # 查内存大户
adb shell "dumpsys deviceidle whitelist +<桌面包名>"                  # 加 Doze 白名单（重启失效）
```

建议用户：**视频 App 用完退出，不要按 HOME 丢后台**。

### 原生桌面无法用 adb 启动

```
SecurityException: starting Intent { cmp=com.mitv.tvhome/.MainActivityUserMode }
requires com.mitv.tvhome.permission.HOME_STATE
```
小米给原生桌面 MainActivity 加了专属权限，**shell 启动不了**。应急回退只能靠遥控器 HOME 键。

---

## 装第三方桌面

```bash
bash scripts/tv_adb.sh install <IP> <apk>    # 推送 + 安装
bash scripts/tv_adb.sh keep    <IP>          # 保活
```

### 首次启动需用户手动同意隐私协议
首启会弹 `AgreementActivity`。**不得代勾隐私协议**——需本人明示同意。

### 主 Activity 名不一定叫 MainActivity
从 `dumpsys package <pkg>` 里读 `android.intent.action.MAIN` 对应项。
- 当贝桌面：`com.dangbei.launcher.ui.main.MainActivity`

### APK 校验
```bash
file <apk>                    # 应为 Zip archive data
shasum -a 256 <apk>           # 记指纹
unzip -p <apk> AndroidManifest.xml | strings | grep -i leanback   # TV 桌面会有 leanback-v17
```
自签证书 `CN=1`、有效期到 2040 是第三方桌面常态。

---

## 广电合规管控导致「安装失败」

**现象**：电视内点安装 → 弹「安装失败：根据互联网电视相关要求，应用存在违规功能，禁止安装」

**这不是技术故障，是广电总局对互联网电视的合规管控。**

**拦截方定位**：
```bash
adb shell "dumpsys package com.mitv.care" | grep -iE "packageinstaller|care"
# com.mitv.care/com.xiaomi.mitv.pie.InstallEventReceiver
#   监听 action: com.android.packageinstaller.ACTION_INSTALL_COMMIT.APPSTORE
```
`com.mitv.care` 里的 PIE = 违规应用拦截组件，**只在商店渠道安装时触发**。

**✅ 正确解法：adb 直装**
```bash
adb shell "pm install -r /data/local/tmp/x.apk"
```
`pm install` 走 shell 通道，**不经过 APPSTORE action**，实测绕过成功，且**完全不动管控组件**。

**❌ 禁止做法**：停用 `com.mitv.care` 绕管控。它是合规管控 + 广告管控双用组件，且涉合规问题须由用户决策。

**排除项**（先查这些，避免误判）：网络（`ping 223.5.5.5`）、存储（`df -h /data`）、版本冲突。

---

## 画质参数（★ 边界明确）

**adb 只能改亮度**：
```bash
adb shell settings get system screen_brightness         # 读（0-255）
adb shell settings put system screen_brightness <值>     # 写（实测生效）
```

**对比度/色温/锐度/饱和度/降噪/背光/图像模式——adb 改不了。**

实测依据：
- `dumpsys tvservice` 只输出**音频**参数，无 PQ（画质）
- `/data/data/com.xiaomi.mitv.settings` → Permission denied（需 root）
- `settings list system` 里图像相关**只有 brightness 一个键**

原因：这些由**芯片厂商的 tvserver 的 PQ 模块**管理（如 Amlogic），不在 Android 层。

> ⚠️ 不要尝试 `service call tvservice` 强改——方法签名未知，可能导致显示异常。

**必须让用户在电视「设置 → 图像与声音」里调**，建议值见 `references/display-tuning.md`。

---

## 远程关机

```bash
adb shell input keyevent KEYCODE_POWER      # ✅ 等同遥控器电源键
```

❌ `am start -a android.intent.action.ACTION_REQUEST_SHUTDOWN` → `SecurityException: requires android.permission.SHUTDOWN`（普通 shell 没有）。

验证：`ping` 不通 + 5555/8009/80 全 closed + mDNS 消失。

---

## 定时执行（可选，需用户自行安装）

⚠️ **WorkBuddy 沙箱内无法安装定时任务**（`crontab` / `launchctl bootstrap` 均被 TCC 拦），必须让用户在终端执行。
⚠️ **装定时任务等于改用户电脑设置，必须先取得同意。** 用户可能不愿意。

**macOS 的两个坑**（实测）：
1. **macOS 默认不启动 cron 服务**（`ps aux | grep -c cron` = 0）→ 装了 crontab 也不执行。需 `sudo launchctl load -w /System/Library/LaunchDaemons/com.vix.cron.plist`
2. cron 的 5 个字段**必须空格分隔**：`* * * * *`（写成 `*/1*` 会失效）

**推荐 launchd**（无需 sudo）：
```bash
# 写入 ~/Library/LaunchAgents/com.tvguard.plist 后：
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.tvguard.plist
launchctl list | grep tvguard
```
plist 关键项：`StartInterval=60`、`RunAtLoad=true`、`EnvironmentVariables.PATH` 要含 adb 目录。

---

## 高风险动作清单（默认不做）

| 动作 | 风险 |
|---|---|
| 禁用唯一桌面 | **黑屏开不了机** |
| `pm uninstall` | 不可逆，系统更新后可能装回来 |
| `remount` / 改 `/system` | 变砖风险 |
| 停 `com.mitv.care` | 合规风险 + 已停的广告服务复活 |
| 停系统更新 `mitv.upgrade` | **静默错过安全补丁且无界面提示** |
| 代勾隐私协议 | 越权 |

副作用需主动告知用户的包：
- `com.xiaomi.mitv.tvpush.tvpushservice` — 桌面首页卡片靠它下发内容，停后可能空白，**副作用/收益比最差**
- `com.xiaomi.mimusic2` — 不影响系统媒体框架（MediaPlayer/AudioFocus 在 system_server），但音乐键可能无响应

---

## 风险评审（涉不可逆动作前必做）

派 2 方独立评审，**只喂实测事实快照，不喂自己的判断**。

codex 沙箱常报 `sandbox_apply: Operation not permitted` 读不到文件 → **把事实直接内联进 prompt 字符串**，不传文件路径。

**保底判据（自查已足够）**：无 root + 无 remount + 未写系统分区 + `pm list packages -d` 前后一致 → **风险低，不会变砖**。

**评审价值在于抓「想当然的结论」**——例如 agent 武断认为「重启即恢复」，实际 stopped 标志的行为要复杂得多。

---

## 交付要求

1. **报告**：设备实测配置、被否方案及原因、已执行命令、健康验证数据、回滚命令
2. **脚本**：带包名存在性校验 + 恢复子命令
3. **状态备份**：禁用清单 + getprop
4. **不做的事要写明**：如「未禁用桌面，因为会黑屏」「未停管控组件，涉及合规」

---

## 踩坑记录（跨项目通用）

**macOS 无 `timeout`** → 用后台作业 + 轮询。**这是之前满屏 `SKIP 设备不可达` 的真凶。**

**macOS 无 `flock`** → 用 `mkdir` 原子锁 + PID 自愈（写 pid 进锁目录，`kill -0` 检查存活）。

**bash 数组分隔符**：`${item%%|*}` 在 macOS 自带 bash 3.2 下解析错位。
✅ 正确用：`IFS="|" read -r p desc <<< "$item"`

**adb 参数不要用变量拼接**：`D="-s <ip>:5555"` 再 `adb $D shell` 会拆成两参报 `-s requires an argument`。用 `S=<ip>:5555` 后 `adb -s $S shell`。

**`get-state` 是 adb 本机命令**，加 `shell` 会被发到电视执行 → `not found`。

**调试脚本要隔离验证**：WorkBuddy 沙箱会注入 bash 初始化环境，某些函数在脚本内表现与隔离环境不同。写个 `/tmp/test.sh` 单测，别只在脚本内猜。

---

## 配套文件

| 文件 | 内容 |
|---|---|
| `scripts/tv_adb.sh` | 主工具箱（9 个子命令） |
| `scripts/tv_guard.sh` | 桌面保活守护（可定时调用） |
| `references/pkg-map-and-errors.md` | 各品牌包名对照 + 错误码速查 |
| `references/display-tuning.md` | 画质参数建议（给用户手动调） |
