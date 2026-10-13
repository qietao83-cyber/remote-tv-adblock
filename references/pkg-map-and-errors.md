# 包名对照与错误码速查

## 一、小米电视包名（按固件年代差异极大）

### 广告与统计类

| 包名 | 作用 | 风险 | 2016 老机型是否存在 |
|---|---|---|---|
| `com.miui.systemAdSolution` | 系统广告服务（开机广告核心） | 低 | ✅ |
| `com.miui.tv.analytics` | 系统埋点统计 | 低 | ✅ |
| `com.xiaomi.statistic` | 小米统计上报 | 低 | ✅ |
| `com.xiaomi.mitv.tvpush.tvpushservice` | 电视推送服务 | 低但**副作用大** | ✅ |
| `com.xiaomi.mitv.upgrade` | 系统 OTA 更新 | 停用会**静默错过安全补丁** | ✅ |

### 预装与冗余类

| 包名 | 作用 | 风险 |
|---|---|---|
| `com.xiaomi.gamecenter.sdk.service.mibox` | 游戏中心 | 低 |
| `com.xiaomi.mimusic2` | 小米音乐（不影响系统媒体框架） | 低，音乐键可能无响应 |
| `com.xiaomi.mimusic2` 同上 | 网上有写错为 `com.miaomi.mimusic2` | — |
| `com.mitv.screensaver` | 屏保 | 低 |
| `com.xiaomi.tweather` | 天气服务 | 低 |
| `com.xiaomi.mitv.appstore` | 小米应用商店 | 低（停用影响装应用） |

### 管控类（★ 不要停）

| 包名 | 作用 |
|---|---|
| `com.mitv.care` | 小米安全管控中心，含 PIE 违规应用拦截 `com.xiaomi.mitv.pie.InstallEventReceiver` |
| `cleantools.mitv.com.tvcleantools` | 系统清理工具 |

### 桌面类

| 网上常见写法 | 实际 | 说明 |
|---|---|---|
| `com.mitv.tvhome.atv` | ❌ 错 | 2016 机型无此后缀 |
| `com.mitv.tvhome.michannel` | ❌ 不存在 | 新版才有 |
| `com.mitv.tvhome` | ✅ 2016 机型 | 主Activity `com.mitv.tvhome.MainActivityUserMode` |
| `com.dangbei.tvlauncher` | 当贝桌面 | 主 Activity `com.dangbei.launcher.ui.main.MainActivity` |
| `com.dangbeimarket` | 当贝市场 | 主 Activity `.activity.WelcomeActivity` |

### 第三方桌面

| 桌面 | 包名 | 主 Activity |
|---|---|---|
| 当贝桌面 | `com.dangbei.tvlauncher` | `com.dangbei.launcher.ui.main.MainActivity` |
| Emotn | `com.emotn.ui` | 视版本 |
| 当贝市场 | `com.dangbeimarket` | `com.dangbeimarket.activity.WelcomeActivity` |

---

## 二、其他品牌电视

| 品牌 | 桌面常见包名 | 备注 |
|---|---|---|
| 小米 | `com.mitv.tvhome` | PatchWall |
| 华为 | `com.huawei.hidisplay` / `com.huawei.android.thememanager` | |
|创维/酷开 | `com.skyworth.epg` | 酷开系统 |
| TCL | `com.tcl.tvta` | |
| 三星 | `com.sec.android.app.launcher` | Tizen 不用 ADB 这套 |
| 海信 | `com.hisense.tvlauncher` | |
| 索尼 | `com.sony.tvhome` | |

⚠️ **一律以 `pm list packages` 实测为准。**

---

## 三、错误码速查

### Connection refused

```
failed to connect to '<电视IP>:5555': Connection refused
```
**含义**：设备在线，5555 端口无进程监听 = **电视侧 ADB 没开**。
**不是** IP 错、不是防火墙、不是网段隔离。
**解决**：电视上「设置 → 关于 → 产品型号」确认键连按 7 次 → 「账号与安全 → ADB 调试」开。部分老机型藏在「设备偏好设置 → 关于」。

### failed to authenticate / device unauthorized

```
failed to authenticate to <电视IP>:5555
error: device unauthorized.
```
**含义**：端口已开，但电视弹了授权框没人点。
**解决**：立刻轮询等 30 秒左右，并**让用户到电视前点「始终允许」**。
```bash
for i in $(seq 1 40); do
  [ "$(adb -s $S get-state 2>/dev/null)" = "device" ] && break
  sleep 5
done
```

### SecurityException: Permission Denial

```
Error: java.lang.SecurityException: Permission Denial: attempt to change
component state from pid=7073, uid=2000, package uid=10018
```
**含义**：该固件把 `CHANGE_COMPONENT_ENABLED_STATE` 从 shell(uid=2000) 移除。**对系统包和普通第三方包全部被拒**。
**解决**：不要重试、不要找 root，转 `am force-stop`。

### SecurityException: MANAGE_USERS

```
Error: java.lang.SecurityException: Neither user 2000 nor current process
has android.permission.MANAGE_USERS.
```
**含义**：`pm hide` 需要 `MANAGE_USERS`，老机型不具备。
**解决**：同上，转 force-stop。

### unknown command 'set-home-activity'

```
Error: unknown command 'set-home-activity'
```
**含义**：Android 6.0 无此命令（Oreo/API 26 才加）。
**解决**：改用自带抢占的桌面（`BootReceiver` + `HomeKeyEventCatchService`），按 HOME 键验证。

### /system/bin/sh: get-state: not found

**含义**：`get-state` 是 **adb 本机命令**，误加了 `shell` 被发到电视执行。
**解决**：`adb -s $S get-state`，不要 `adb -s $S shell get-state`。

### 安装失败：违规功能禁止安装

**画面提示**：「根据互联网电视相关要求，应用存在违规功能，禁止安装」

**含义**：广电总局对互联网电视的合规管控，终端拦截未获批应用。**不是技术故障**。
**拦截方**：`com.mitv.care` 的 `com.xiaomi.mitv.pie.InstallEventReceiver`，监听
`com.android.packageinstaller.ACTION_INSTALL_COMMIT.APPSTORE`（**仅商店渠道触发**）。
**解决**：`adb shell pm install -r <apk>` ——走 shell 通道，绕过该 action。
**禁止**：停用 `com.mitv.care`（合规 + 广告双用组件）。

### /system/bin/sh: su: not found

无 root。`/system` 通常挂载为 `ro`（只读）。别尝试 remount。

---

## 四、验证健康状态标准命令

```bash
# 桌面焦点（判当前界面）
adb shell "dumpsys window windows" | grep mCurrentFocus

# 唤醒并回桌面（查健康前必做，否则待机态会误判）
adb shell input keyevent KEYCODE_WAKEUP
adb shell input keyevent KEYCODE_HOME

# 崩溃检查（必须为 0）
adb shell "logcat -d -b crash -t 30" | grep -ci FATAL

# 桌面包是否被永久改动（应为 enabled/未禁用）
adb shell "dumpsys package com.mitv.tvhome" | grep -oE "stopped=(true|false)|enabled=(true|false)"

# stopped 标志（force-stop 后为 true，重启不会清）
adb shell "dumpsys package <pkg>" | grep -oE "stopped=(true|false)"

# 永久禁用清单（与备份对比，应无新增）
adb shell pm list packages -d
```

**焦点窗口解读**：

| 焦点内容 | 含义 |
|---|---|
| `com.mitv.tvhome/...MainActivityUserMode` | 原生桌面正常 |
| `com.dangbei.tvlauncher...` | 当贝桌面 |
| `com.mitv.screensaver...RenderActivity` | 待机屏保（**正常，非异常**） |
| `com.android.packageinstaller/...GrantPermissionsActivity` | 权限申请页，等用户操作 |
| `com.android.packageinstaller/...InstallAppProgress` | 安装进行中 |
| `mCurrentFocus=null` | 可能刚启动未渲染完，等几秒复查 |

---

## 五、stopped 标志与恢复

| 场景 | 表现 | 恢复方式 |
|---|---|---|
| force-stop 服务类包（被 system bind） | 重启后 `stopped` 自动变 false，服务复活 | 无需恢复（系统自己拉起）——**所以必须配开机自启** |
| force-stop 非依赖包 | `stopped=true` 保留，重启后仍停 | `am startservice -n <pkg>/<Service>` 或电视上打开该应用 |
| 桌面停用（disable-user） | 图标消失，`enabled=false` | `pm enable --user 0 <pkg>` |
| 万能兜底 | — | 恢复出厂设置（**会清数据**） |

⚠️ Android 6.0 上命令是 `am startservice`，`am start-service` 是 Oreo 才有的写法。

⚠️ **「重启就能恢复」是个误导说法**：重启只是让系统顺带把服务 bind 回来，**不等于解除停止状态**。要主动清除 stopped，必须启动该包任一组件。

### 小米电视重启后的两件事

1. **广告服务复活**（被 bind 的那批）→ 重跑 `tv_adb.sh deadbiz`
2. **ADB 调试自动关闭** → 电视上手动重开

**快速诊断**：`5555/8009/8008/8080/80` 全部关闭 → 系统重启过。