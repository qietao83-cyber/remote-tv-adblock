# 远程关闭电视广告（remote-tv-adblock）

通过 ADB 远程优化安卓电视与电视盒子：**去广告、装第三方桌面、绕过广电合规安装拦截**。

沉淀自一次真实的小米电视实操（MiTV4-ANSM0 / Android 6.0.1）。那份网上流传的方案里，**11 个包名有 5 个是错的**，核心命令权限被拒完全跑不了，照顺序执行还会黑屏。这个 Skill 记录了怎么避开这些坑。

---

## 能力

| 能力 | 说明 |
|---|---|
| 远程去广告 | 停用广告/统计/推送服务，操作前后做健康验证 |
| 装第三方桌面 | 当贝/ Emotn 等，并验证开机直达 + 保留回退能力 |
| 绕过广电合规拦截 | 「提示违规功能禁止安装」用 adb 直装绕过，不动管控组件 |
| 风险评估 | 高风险动作清单 + 桌面健康验证闸门 + 回滚路径 |

---

## 核心教训（为什么不照抄现成方案）

### 1. 不同年份机型，包名和权限机制完全不同

网上教程基本都针对新版 PatchWall 写的。实测对照：

|网上常见写法 | 2016 老机型实际 |
|---|---|
| `com.mitv.tvhome.atv` | `com.mitv.tvhome` |
| `com.mitv.tvhome.michannel` | 无此包 |
| `com.xiaomi.mitv.advertise` | 无此包 |
| `com.xiaomi.mibox.gamecenter` | `com.xiaomi.gamecenter.sdk.service.mibox` |

**永远以 `pm list packages` 实测为准。**

### 2. `pm disable-user` 会静默失败

老机型固件把 `CHANGE_COMPONENT_ENABLED_STATE` 从 shell 账号移除，报错：

```
java.lang.SecurityException: Permission Denial: attempt to change component state from uid=2000
```

**对系统包和普通第三方包全部被拒。** 所以动手前必须先探测权限边界，再决定用哪条命令。

### 3. `force-stop` ≠ 禁用，且「重启」不能恢复

`am force-stop` 的语义是 **杀进程 + 在 packages.xml 置 `stopped="true"`**，该标志**跨重启保留**。

> ⚠️ 「重启电视就恢复了」是错的。恢复方式是启动该包任一组件（`am startservice`），或在电视上打开该应用一次。

### 4. 桌面永远不动

禁用唯一桌面 = 直接黑屏开不了机。除非已装好第三方桌面，否则一律保留原生。

---

## 安装

### 方式一 · SkillHub（WorkBuddy 技能市场）

```bash
skillhub install user_7a89592b/remote-tv-adblock
```

或直接在 WorkBuddy 应用内搜索「远程关闭电视广告」。

### 方式二 · 手动安装

下载本仓库的 zip，解压到 `~/.workbuddy/skills/remote-tv-adblock/` 即可。

**依赖**：`adb`（platform-tools）

```bash
# macOS 推荐直装官方包（brew 常因 GitHub 网络受限失败）
mkdir -p ~/tools/android && cd ~/tools/android
curl -L -o pt.zip "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
unzip -q pt.zip
export PATH="$HOME/tools/android/platform-tools:$PATH"
```

---

## 使用

```bash
# 开启电视 ADB（需用户在电视上操作）
# 设置 → 关于 → 产品型号 → 确认键连按 7 次
# 设置 → 账号与安全 → ADB 调试 → 开

bash scripts/tv_adb.sh probe    <IP>   # 体检：机型/权限边界/桌面健康（首次必跑）
bash scripts/tv_adb.sh deadbiz <IP>   # 去广告
bash scripts/tv_adb.sh status   <IP>   # 状态 + 健康检查
bash scripts/tv_adb.sh restore  <IP>   # 恢复被停的服务
bash scripts/tv_adb.sh launcher <IP>   # 桌面管理
```

首次 `probe` 输出示例（老机型）：

```
=== 权限边界探测（决定用什么命令）===
  pm disable-user : [不可用] 权限被拒 → 用 force-stop
  am force-stop  : [可用] ← 唯一推荐手段
  /system: ro（只读）
```

---

## 常用命令速查

### 定位设备（用 mDNS，比 ping 扫描快得多）

```bash
dns-sd -B _airplay._tcp local
```

### 连接与等授权

```bash
adb connect <IP>:5555
for i in $(seq 1 40); do
  [ "$(adb -s <IP>:5555 get-state 2>/dev/null)" = "device" ] && break
  sleep 5
done
```
> 首次连接电视会弹授权框，**必须在电视上点「始终允许」**。

### 绕过广电合规拦截

```bash
adb push <apk> /data/local/tmp/x.apk
adb shell "pm install -r /data/local/tmp/x.apk"   # 走 shell 通道，不触发 APPSTORE 拦截
adb shell "rm -f /data/local/tmp/x.apk"
```

拦截方是 `com.mitv.care` 的 `com.xiaomi.mitv.pie.InstallEventReceiver`，只监听商店渠道 action。

### 健康验证（三项必查）

```bash
adb shell input keyevent KEYCODE_WAKEUP
adb shell input keyevent KEYCODE_HOME; sleep 4
adb shell "dumpsys window windows" | grep mCurrentFocus      # 桌面是否正常
adb shell "logcat -d -b crash -t 30" | grep -ci FATAL        # 必须为 0
adb shell pm list packages -d                # 应无新增永久禁用
```

---

## 高风险动作（默认不做）

| 动作 | 风险 |
|---|---|
| 禁用唯一桌面 | **黑屏开不了机** |
| `pm uninstall` | 不可逆 |
| `remount` / 改 `/system` | 变砖风险 |
| 停 `com.mitv.care` | 合规风险 + 已停的广告服务复活 |
| 停系统更新 | **静默错过安全补丁且无界面提示** |
| 代勾隐私协议 | 越权 |

**副作用需主动告知**：
- `com.xiaomi.mitv.tvpush.tvpushservice` — 桌面首页卡片靠它下发内容，停后可能空白，副作用/收益比最差
- `com.xiaomi.mimusic2` — 不影响系统媒体框架（MediaPlayer/AudioFocus 在 system_server），但音乐键可能无响应

---

## 回滚

```bash
bash scripts/tv_adb.sh restore <IP>     # 恢复被停服务
# 或在电视上手动打开对应应用一次（自动清除 stopped 标志）

# 切回原生桌面
adb -s <IP>:5555 shell am start -n com.mitv.tvhome/com.mitv.tvhome.MainActivityUserMode
# 彻底卸载第三方桌面（-k 保留数据）
adb -s <IP>:5555 shell pm uninstall -k --user 0 <桌面包名>
```

兜底：恢复出厂设置（**会清数据，慎用**）。

---

## 目录结构

```
remote-tv-adblock/
├── SKILL.md                              七步流程 + 铁律 + 关键机制
├── scripts/
│   └── tv_adb.sh                probe/deadbiz/status/restore/launcher
└── references/
    └── pkg-map-and-errors.md            各品牌包名对照 + 错误码速查
```

---

## 注意事项

- 本Skill 仅执行 `force-stop` 等**无损可逆**操作，不做 `disable-user`/`uninstall`/`remount`
- 不修改系统分区，不 root，**不会变砖**
- 用户隐私协议**必须本人手动同意**，工具不会代勾
- 「开机提速 30%-50%」类宣传无实测依据，请勿轻信

---

日期：2026-10-13