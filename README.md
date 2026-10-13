# 远程关闭电视广告（remote-tv-adblock）

通过 ADB 远程优化安卓电视与电视盒子：**去广告、装第三方桌面并保活、绕过广电合规安装拦截、远程关机、画质参数指引**。

沉淀自一次真实的小米电视实操（MiTV4-ANSM0 / Android 6.0.1）。那份网上流传的方案里，**11 个包名有 5 个是错的**，核心命令权限被拒完全跑不了，照顺序执行还会黑屏。这个 Skill 记录了怎么避开这些坑。

---

## 能力

| 能力 | 说明 |
|---|---|
| 远程去广告 | 停用广告/统计/推送服务，操作前后做健康验证 |
| 装第三方桌面 | 推送 + 安装 + 保活，保留回退能力 |
| **桌面保活** | 解决「第三方桌面被原生抢回去」——**保活而非压制** |
| 绕过广电合规拦截 | 「提示违规功能禁止安装」用 adb 直装绕过，不动管控组件 |
| 远程关机 | 等同遥控器电源键 |
| 画质参数指引 | 明确 adb 的能力边界 + 给用户的调参建议 |
| 风险评估 | 高风险动作清单 + 健康验证闸门 + 回滚路径 |

---

## 快速开始

```bash
bash scripts/tv_adb.sh probe    <IP>          # 体检（首次必跑）
bash scripts/tv_adb.sh deadbiz  <IP>          # 去广告
bash scripts/tv_adb.sh install  <IP> <apk>    # 装 APK（绕过广电拦截）
bash scripts/tv_adb.sh keep     <IP>          # 保活第三方桌面
bash scripts/tv_adb.sh status   <IP>          # 状态查看
bash scripts/tv_adb.sh power    <IP>          # 关机
```

依赖 `adb`：
```bash
mkdir -p ~/tools/android && cd ~/tools/android
curl -L -o pt.zip "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
unzip -q pt.zip
export PATH="$HOME/tools/android/platform-tools:$PATH"
```

---

## 核心教训

### 1. 不同年份机型，包名和权限机制完全不同

网上教程基本都针对新版 PatchWall 写的。实测对照：

| 网上常见写法 | 实际（2016 老机型） |
|---|---|
| `com.mitv.tvhome.atv` | `com.mitv.tvhome` |
| `com.mitv.tvhome.michannel` | 无此包 |
| `com.xiaomi.mitv.advertise` | 无此包 |
| `com.xiaomi.mibox.gamecenter` | `com.xiaomi.gamecenter.sdk.service.mibox` |

**永远以 `pm list packages` 实测为准。**

### 2. `pm disable-user` 会静默失败

老机型固件把 `CHANGE_COMPONENT_ENABLED_STATE` 从 shell 账号移除：

```
java.lang.SecurityException: Permission Denial: attempt to change component state from uid=2000
```

**对系统包和普通第三方包全部被拒。** 不要重试、不要找 root，改用 `am force-stop`。

### 3. `force-stop` ≠ 禁用，重启后大概率自动恢复

`am force-stop` = 杀进程 + 置 `stopped="true"`。这个标志**并非一律跨重启保留**：

| 包类型 | 重启后 | 原因 |
|---|---|---|
| **提供 Binder 服务的**（广告/统计/推送） | ❌ 自动复活 | system_server 启动时 bind，**绑定动作即清 stopped** |
| **不被系统依赖的** | ✅ 保持停止 | 无 bind 方 |

> **force-stop 是会话内的临时抑制，不是持久禁用。**

⚠️ 恢复方式永远是「启动该包任一组件」，**不是「重启」**。

### 4. 老电视 `ps -A` 不可用

```bash
$ adb shell "ps -A"
USER  PID  PPID  VSIZE  RSS  WCHAN  PC  NAME     ← 只有表头
```

`ps -A | grep -c <包名>` **恒为 0**，判断进程存活会全部误判。
✅ 改用 `dumpsys activity processes | grep -c <包名>`

---

## 桌面保活（最有价值的部分）

### 为什么设不了系统默认桌面

原生桌面是 **PRIVILEGED 特权应用**，Android 的 IntentResolver 中**特权应用永远优先**。无 root 翻不过来：

| 手段 | 结果 |
|---|---|
| `pm set-home-activity` | Android 6.0 **无此命令**（Oreo 才加） |
| `pm disable/hide` 原生桌面 | SecurityException |
| 写 `preferred-activities.xml` | 无写权限（需 root） |

### ✅ 正确解法：保活，而不是压制

**实测数据**：

| 场景 | 耗时 | 结果 |
|---|---|---|
| 第三方桌面**进程存活** | **0.15-0.26 秒** | ✅ 按 HOME 直接进 |
| 第三方桌面**被内存回收** | 0.3-2.2 秒 | ❌ 先落原生桌面再切（跳两次） |

**关键**：第三方桌面自带 `HomeKeyEventCatchService`，**进程活着时能直接接住 HOME 键**。

> ❌ 错误做法：`force-stop` 原生桌面 —— 会让系统重新 bind 它，**反而拖慢响应**
> ✅ 正确做法：**保住第三方桌面进程存活**

### 进程为什么会被回收

1.6GB 老机器上，视频类 App 动辄占 200MB+，桌面被挤出内存。

```bash
adb shell "dumpsys meminfo" | sed -n '/Total PSS by process/,+14p'   # 查内存大户
adb shell "dumpsys deviceidle whitelist +<桌面包名>"                  # Doze 白名单
```

**建议**：视频 App 用完退出，别按 HOME 丢后台。

---

## 绕过广电合规拦截

现象：「安装失败：根据互联网电视相关要求，应用存在违规功能，禁止安装」

**拦截方**：`com.mitv.care` 的 `com.xiaomi.mitv.pie.InstallEventReceiver`，
监听 `com.android.packageinstaller.ACTION_INSTALL_COMMIT.APPSTORE`（**仅商店渠道触发**）。

**✅ 解法**：`adb shell pm install -r <apk>` —— 走 shell 通道，不经过该 action。

**❌ 禁止**：停用 `com.mitv.care`（合规 + 广告双用组件，且涉合规问题）。

---

## 画质参数的边界

**adb 只能改亮度**：
```bash
adb shell settings put system screen_brightness 150   # 0-255
```

**对比度/色温/锐度/饱和度/降噪/背光——adb 改不了。**
它们由芯片 tvserver 的 PQ 模块管理（如 Amlogic），不在 Android 层。

实测依据：`dumpsys tvservice` 只输出音频参数；`/data/data/com.xiaomi.mitv.settings` 需 root。

**必须让用户在电视上手动调**，建议值见 `references/display-tuning.md`。

---

## 踩坑记录（跨项目通用）

| 坑 | 现象 | 解决 |
|---|---|---|
| **macOS 无 `timeout`** | `command not found` | 后台作业 + 轮询 kill |
| **macOS 无 `flock`** | `command not found` | `mkdir` 原子锁 + PID 自愈 |
| **macOS cron 默认不跑** | `crontab -l` 有内容但不动 | `sudo launchctl load -w /System/Library/LaunchDaemons/com.vix.cron.plist` |
| **`launchctl load` 已废弃** | `Input/output error` | 用 `launchctl bootstrap gui/$(id -u) <plist>` |
| **cron 字段要空格** | `*/1*` 失效 | 写 `* * * * *` |
| **bash 数组分隔符** | `${item%%\|*}` 解析错位 | `IFS="\|" read -r p desc <<< "$item"` |
| **adb 参数拼接** | `-s requires an argument` | 用 `S=<ip>:5555` 后 `adb -s $S` |
| **`get-state` 误加 shell** | `not found` | `get-state` 是 adb 本机命令 |

---

## 目录结构

```
remote-tv-adblock/
├── SKILL.md                              完整流程 + 铁律 + 机制说明
├── scripts/
│   ├── tv_adb.sh                         主工具箱（9 子命令）
│   └── tv_guard.sh                       桌面保活守护（可定时）
└── references/
    ├── pkg-map-and-errors.md             包名对照 + 错误码速查
    └── display-tuning.md                 画质参数建议
```

---

## 注意事项

- 只执行 `force-stop` / `am start` 等**无损可逆**操作，不做 `disable-user` / `uninstall` / `remount`
- 不修改系统分区，不 root，**不会变砖**
- 用户隐私协议**必须本人手动同意**，工具不会代勾
- 装定时任务等于**改用户电脑设置**，须先取得同意
- 「开机提速 30%-50%」类宣传无实测依据，请勿轻信

---

## License

MIT

日期：2026-10-13
