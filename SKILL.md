---
name: remote-tv-adblock
slug: remote-tv-adblock
displayName: 远程关闭电视广告
version: "1.0.0"
summary: 通过 ADB 远程优化安卓电视/盒子：去广告、装第三方桌面、绕过广电合规拦截。强制先核实机型固件与权限边界再动手，只执行实测可用命令，操作前后必做健康验证与状态备份。
license: MIT-0
description: "通过 ADB 远程优化安卓电视与电视盒子——去广告、装第三方桌面、绕过广电合规安装拦截。当用户要求「优化小米电视/电视去广告/电视开机提速/装当贝桌面/电视卡顿/换电视桌面/电视装不了应用/提示违规功能禁止安装」，或提供电视 IP 要求远程操作电视时使用。强制先核实机型固件与权限边界再动手：不同年份机型包名与权限机制完全不同，照抄网上教程会静默失败或黑屏。只执行实测可用命令（老机型上 pm disable-user 会被权限拒，用 am force-stop 替代），操作前后必做健康验证与状态备份。★沉淀自 MiTV4-ANSM0(Android 6.0.1) 实战：AI 生成的方案 11 个包名 5 个是错的、核心命令权限被拒完全跑不了、照顺序执行会黑屏。触发词：优化电视、电视去广告、去广告、开电视ADB、装当贝桌面、换桌面、电视装不了应用、安装失败、违规功能禁止安装、电视提速、电视优化、ADB电视、远程改电视、盒子去广告、电视广告多。"
agent_created: true
---

# 远程关闭电视广告

> 由来：2026-10-13 客厅小米电视 MiTV4-ANSM0 实操。二手教程（AI 生成）给的方案 **11 个包名5 个是错的**、**核心命令权限被拒完全跑不了**、**照顺序执行会黑屏**。改用实测路径后完成，并靠多方评审发现「重启即恢复」这条结论本身是错的。

## 铁律

**1. 不照抄任何现成方案，先核实再执行。** AI 生成的电视优化教程几乎都是给新版 PatchWall 写的，老机型上包名全不一样。且 `pm disable-user` 会**静默失败——不报错 ≠ 生效**。

**2. 动手前必须核实两件事**（决定后续所有命令选型）：
```bash
adb shell getprop ro.build.version.release    # Android 版本
adb shell getprop ro.build.version.incremental # 固件版本
adb shell pm list packages                     # 真实存在的包
```
Android 6.0（SDK 23）与 Android 9+ 权限模型完全不同，命令集不通用。

**3. 桌面永远不动。** 禁用唯一桌面 = 直接黑屏开不了机。除非用户明确要求换桌面且已装好第三方桌面，否则一律保留原生。

**4. 每次改完必验健康状态**，三项缺一不可（见「验证闸门」）。

**5. 只做 `force-stop`，不做 `disable-user`/`uninstall`/`remount`。** 前者无损可逆，后者可能永久改动且需 root。

---

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
dns-sd -B _airplay._tcp local# 2 秒出结果，比 ping 扫描快得多
dns-sd -L "<设备名>" _airplay._tcp local   # 取详情（含 MAC）
```
拿到 MAC 后 `arp -a | grep <MAC 片段>` 反查 IP。macOS 无线网卡走 en0。

### 第 3 步 · 确认电视侧 ADB 已开

```bash
nc -z -G 2 <IP> 5555
```
- `Connection refused` → 电视在线但 ADB 没开（**最常见**，不是 IP 错、不是防火墙、不是网段隔离）
- `succeeded` → 已开

**开 ADB（用户操作，AI 不可代办）**：设置 → 关于 → 产品型号 → 确认键 **连按 7 次** → 设置 → 账号与安全 → ADB 调试 → 开。
部分老机型把ADB 藏在「设备偏好设置 → 关于 → 产品型号」里。

```bash
adb connect <IP>:5555
# 轮询等待授权 —— 电视弹框必须有人点「始终允许」
for i in $(seq 1 40); do
  [ "$(adb -s <IP>:5555 get-state 2>/dev/null)" = "device" ] && break
  sleep 5
done
```
授权通常需 30 秒左右。**必须提前告知用户到电视前点确认**，否则会卡死。

### 第 4 步 · 备份现状（必做，回滚依据）

```bash
BK=~/tv-opt/backup_$(date +%Y%m%d_%H%M%S); mkdir -p "$BK"
adb shell pm list packages -d > "$BK/disabled_before.txt"   # 已禁用清单
adb shell pm list packages -s > "$BK/system_pkgs_before.txt"
adb shell getprop> "$BK/getprop.txt"
```

### 第 5 步 · 探测权限边界（决定用什么命令）

依次试，**记录哪个成功哪个失败**：

| 命令 | 预期结果 |
|---|---|
| `pm disable-user --user 0 <pkg>` | 多数机型 SecurityException |
| `pm hide <pkg>` | 多数机型 SecurityException |
| `which su` | 无 root 则 not found |
| `mount \| grep system` | 通常 `ro`（只读） |
| **`am force-stop <pkg>`** | **几乎必然成功 ← 唯一可用手段** |

**典型 SecurityException 含义**：
```
java.lang.SecurityException: Permission Denial: attempt to change component state from uid=2000
```
→ 该固件把 `MANAGE_USERS` / `CHANGE_COMPONENT_ENABLED_STATE` 从 shell 账号移除。**对系统包和普通第三方包全部被拒**（实测普通应用 `com.gitvdemo.video` 同样被拒）。此时不要重试、不要找 root，直接转 force-stop 路线。

### 第 6 步 · 执行（用脚本，不要裸敲）

`scripts/tv_adb.sh` 提供 5 个子命令，**每个都做包名存在性校验**（杜绝静默失败）：

```bash
bash scripts/tv_adb.sh probe    <IP>   # 体检：机型/权限/桌面健康
bash scripts/tv_adb.sh deadbiz <IP>   # 去广告（force-stop）
bash scripts/tv_adb.sh status   <IP>   # 状态 + 健康检查
bash scripts/tv_adb.sh restore  <IP>   # 恢复被停服务
bash scripts/tv_adb.sh launcher <IP>   # 桌面管理 / 切回原生
```

### 第 7 步 · 验证闸门（三项全过才算完成）

```bash
adb shell "dumpsys window windows" | grep mCurrentFocus        # 桌面是否正常
adb shell "dumpsys package com.mitv.tvhome" | grep -oE "stopped=(true|false)"
adb shell "logcat -d -b crash -t 30" | grep -ci FATAL          # 必须为 0
adb shell pm list packages -d                # 与备份对比，无新增永久禁用
```
另外**必须实测唤醒后桌面可回**：
```bash
adb shell input keyevent KEYCODE_WAKEUP; adb shell input keyevent KEYCODE_HOME
sleep 4; adb shell "dumpsys window windows" | grep mCurrentFocus
```
待机时焦点在 `com.mitv.screensaver` 属正常，不是异常。

---

## 关键机制（★ 最容易搞错，必读）

### force-stop ≠ 禁用，且重启后大概率自动恢复

`am force-stop` = **杀进程 + 置 `stopped="true"` 标志**。但这个标志**并非一律跨重启保留**——实测（MiTV4-ANSM0）：

| 包类型 | 重启后 | 原因 |
|---|---|---|
| **提供 Binder 服务的包**（广告服务、统计、推送） | ❌ stopped 被清除，**服务自动拉起** | system_server 启动时会 bind 它们，**绑定动作即清 stopped** |
| **不被系统依赖的包**（游戏中心、小米音乐） | ✅ stopped=true **保留，仍停** | 无 bind 方，没人拉起 |

> **实测验证命令**：
> ```bash
> adb shell "dumpsys package <pkg>" | grep -oE "stopped=(true|false)"
> ```
> 重启前后各跑一次即可确认。

**正确结论**：
> force-stop 是**「本次会话内」的临时抑制，不是持久禁用**。
> 停广告前先想清楚：**目标包是不是被系统 bind 的服务包？** 是的话，重启后必然复活，stop 只能管到下次重启。
> **要持久，必须配开机自启**（见 `startup`）。

| | force-stop | pm disable-user |
|---|---|---|
| `enabled` 状态 | 保持 enabled | 改为 DISABLED_USER |
| 重启后 | **视是否被 bind 而定** | 保持禁用 |
| 桌面图标 | 正常可见 | 消失 |
| 恢复方式 | **启动任一组件即自动清除 stopped** | `pm enable` |

⚠️ **恢复方式永远是「启动该包任一组件」**（`am startservice` 或电视上手动打开），**不是「重启」**。重启只会让系统顺带恢复它，不算「解除」。

### 包被 bind 会自动复活（★这是重启后广告复现的根因）

提供 Binder 服务的包会被系统自己 bind 拉起，`stopped` 被清除并照常运行。

**实测证据**（MiTV4-ANSM0 重启后）：
```
com.miui.systemAdSolution     stopped=false  ← 被拉回
com.miui.tv.analytics         stopped=false  ← 被拉回
com.xiaomi.statistic          stopped=false  ← 被拉回
com.xiaomi.mitv.tvpush...     stopped=false  ← 被拉回
com.xiaomi.gamecenter...mibox stopped=true   ← 保留
com.xiaomi.mimusic2           stopped=true   ← 保留
```

**所以停广告必须配开机自启**，否则每次重启都要手动重来。

### 小米电视重启会连带断掉远程能力

重启后：
1. 广告服务复活（被 bind 的那些）
2. **ADB 调试自动关闭** → 需到电视上手动重开

**快速指纹**：电视在线但 5555/8009/8008/8080/80 **全部 refused/closed** → 判断"系统重启过"（正常待机时 5555 是开的）。

→ 这也是为什么 `startup` 自启很关键：不配的话，重启一次就得手动补救两件事（开 ADB + 重跑 stop）。

### 包名跨机型不通用

| 网上常见写法 | 2016 老机型实际 |
|---|---|
| `com.mitv.tvhome.atv` | `com.mitv.tvhome` |
| `com.mitv.tvhome.michannel` | 无此包 |
| `com.xiaomi.mitv.advertise` | 无此包 |
| `com.xiaomi.mibox.gamecenter` | `com.xiaomi.gamecenter.sdk.service.mibox` |
| `com.miui.systemAdSolution` | ✅ 通用 |

**永远以 `pm list packages` 实测为准。**

---

## 装第三方桌面

### 优先级判断
- Android 8+：`pm set-home-activity <pkg>/<Activity>` 可用
- **Android 6.0：无此命令**（Oreo 才加，带 `--user` 也不行，报 unknown command）
- **但多数桌面自带抢占机制，无需设默认**：`BootReceiver`（BOOT_COMPLETED 自启）+ `HomeKeyEventCatchService`（拦 HOME 键）

验证是否已生效（比设默认更可靠）：
```bash
adb shell input keyevent KEYCODE_HOME; sleep 4
adb shell "dumpsys window windows" | grep mCurrentFocus   # 是否为目标桌面
```
连按多次确认稳定：焦点 window id 应**保持不变**（id 变化 = 在反复重启 = 异常）。

### 安装流程
```bash
adb push <apk> /data/local/tmp/x.apk
adb shell "pm install -r /data/local/tmp/x.apk"
adb shell pm list packages | grep -i <关键字>          # 确认真实包名
adb shell "rm -f /data/local/tmp/x.apk"                 # 清理
```

### 首次启动需用户手动同意隐私协议
第三方桌面首启会弹 `AgreementActivity`。**AI 不得代勾隐私协议**——需本人明示同意。启动后检查焦点，告知用户在电视上完成授权，后续权限页（`GrantPermissionsActivity`）同理。

⚠️ 主 Activity 名不一定叫 `MainActivity`，从 `dumpsys package` 读 `android.intent.action.MAIN` 对应项。

### APK 校验（装之前）
```bash
file <apk>                    # 应为 Zip archive data
shasum -a 256 <apk>           # 记指纹
unzip -p <apk> AndroidManifest.xml | strings | grep -i leanback   # TV 桌面会有 leanback-v17
```
自签证书 `CN=1`、有效期到 2040 是第三方桌面常态，不必报警。

---

## 广电合规管控导致「安装失败」（高频问题）

**现象**：电视内点安装应用 → 弹「安装失败：根据互联网电视相关要求，应用存在违规功能，禁止安装」

**这不是技术故障，是广电总局对互联网电视的合规管控**（终端须拦截未获批应用）。

**拦截方定位**：
```bash
adb shell "dumpsys package com.mitv.care" | grep -iE "packageinstaller|care"
# com.mitv.care/com.xiaomi.mitv.pie.InstallEventReceiver
#   监听 action: com.android.packageinstaller.ACTION_INSTALL_COMMIT.APPSTORE
```
`com.mitv.care`（小米安全管控中心）里的 PIE =违规应用拦截组件，**只在商店渠道安装时触发**。

**✅ 正确解法：adb 直装**
```bash
adb shell "pm install -r /data/local/tmp/<apk>"
```
`pm install` 走 shell 通道，**不经过 APPSTORE action**，实测成功绕过，且**完全不动管控组件**。

**❌ 禁止做法**：停用 `com.mitv.care` 绕管控。它是合规管控 + 广告管控双用组件，停掉可能让已停的广告服务复活，且涉合规问题须由用户决策。

**排除项**（先查这些，避免误判为黑名单）：网络（`ping 223.5.5.5`）、存储（`df -h /data`）、版本冲突（先确认同类应用能否装上）。

---

## 高风险动作清单（默认不做）

| 动作 | 风险 |
|---|---|
| 禁用唯一桌面 | **黑屏开不了机**，除非已装第三方桌面 |
| `pm uninstall` | 不可逆，系统更新后可能装回来 |
| `remount` / 改 `/system` | 变砖风险 |
| 停 `com.mitv.care` | 合规风险 + 广告服务复活 |
| 停系统更新 `mitv.upgrade` | **静默错过安全补丁且无界面提示**（实测会被系统自动 bind 拉回） |
| 代勾隐私协议 | 越权 |

副作用需主动告知用户的包：
- `com.xiaomi.mitv.tvpush.tvpushservice` — 桌面首页卡片靠它下发内容，停后可能空白/不刷新，**副作用/收益比最差**
- `com.xiaomi.mimusic2` — 不影响系统媒体框架（MediaPlayer / AudioFocus / MediaSession 都在 system_server），但音乐键可能无响应

---

## 风险评审（涉不可逆动作前必做）

派 2 方独立评审（大G Codex + Android 工程师子代理），**只喂实测事实快照，不喂自己的判断**。

codex 沙箱常报 `sandbox-exec: sandbox_apply: Operation not permitted` 读不到任何文件 → **把事实直接内联进 prompt 字符串**，不传文件路径。这招实测有效。

**保底判据（自查已足够）**：无 root + 无 remount + 未写系统分区 + `pm list packages -d` 前后一致 → **风险低，不会变砖**，最坏是体验层（首页不刷新/音乐键无响应）。

评审常纠正的错误认知：agent 会武断认为「重启即恢复」，实际 stopped 标志持久化。**评审价值在于抓这类想当然的结论。**

---

## 交付要求

1. **报告**（MD）：设备实测配置、被否方案及原因、已执行命令、健康验证数据、回滚命令
2. **可执行脚本**：带包名存在性校验 + 恢复子命令
3. **状态备份**：禁用清单 + getprop
4. **不做的事要写明**：如「未禁用桌面，因为会黑屏」「未停管控组件，涉及合规」

---

## 踩坑记录

**bash 数组分隔符**：`${item%%|*}` 在 macOS 自带 bash 3.2 下解析错位。**正确用** `IFS="|" read -r p desc <<< "$item"`。

**adb 参数**：不要写 `D="-s <ip>:5555"` 再 `adb $D shell`（带空格会拆成两参，报 `-s requires an argument`）。用 `S=<ip>:5555` 后 `adb -s $S shell`。

**`get-state` 是 adb 本机命令**，加 `shell` 会被发到电视执行 → `/system/bin/sh: get-state: not found`。

**Windows 输出带 `\r`**：所有 `adb shell` 输出接 `| tr -d '\r'`，否则字符串比对全部失败。

**待机态焦点是屏保**：查桌面健康前先发 `KEYCODE_WAKEUP`，否则会误判桌面挂了。

**等授权别只试一次**：连上后跑轮询脚本等 30 秒左右，第一次失败不代表失败。

---

## 配套脚本

`scripts/tv_adb.sh` — 通用脚本，参数为 TV IP：
```bash
bash scripts/tv_adb.sh probe    <IP>   # 体检（首次必跑）
bash scripts/tv_adb.sh deadbiz <IP>   # 去广告
bash scripts/tv_adb.sh status   <IP>   # 状态
bash scripts/tv_adb.sh restore  <IP>   # 恢复
bash scripts/tv_adb.sh launcher <IP>   # 桌面管理
```
`references/` 内含各家厂商包名对照与错误码速查。