#!/bin/bash
# 安卓电视/盒子 ADB 远程工具箱
#
# 适用：小米/小米盒子为主，其他品牌需替换包名（见 references/pkg-map-and-errors.md）
#
# 用法:
#   bash tv_adb.sh probe      <IP>              体检（机型/权限边界/桌面/内存）★首次必跑
#   bash tv_adb.sh status     <IP>              状态查看
#   bash tv_adb.sh deadbiz    <IP>              去广告
#   bash tv_adb.sh install    <IP> <apk路径>    安装 APK（绕过广电合规拦截）
#   bash tv_adb.sh launcher   <IP>              桌面管理（含特权分析）
#   bash tv_adb.sh keep       <IP> [包名]       桌面保活（唤起指定桌面，默认当贝）
#   bash tv_adb.sh power      <IP>              关机（等同遥控器电源键）
#   bash tv_adb.sh brightness <IP> [0-255]      读取或设置亮度
#   bash tv_adb.sh restore    <IP>              恢复被停用的服务
#
# 设计要点（全部来自实测踩坑，勿改）:
#   1. macOS 无 timeout 命令 → 用后台作业 + 轮询实现超时
#   2. 老电视 ps -A 只输出表头 → 用 dumpsys activity processes 判断进程
#   3. 所有 adb shell 输出接 tr -d '\r'（否则字符串比对全失败）
#   4. 包名操作前先校验存在性 → 防止静默失败（不报错 ≠ 生效）

set -uo pipefail

ADB_DIR="$HOME/tools/android/platform-tools"
[ -x "$ADB_DIR/adb" ] && export PATH="$ADB_DIR:$PATH"

CMD="${1:-}"
IP="${2:-}"
S="${IP}:5555"

# ========== 基础工具 ==========

# 超时执行（macOS 没有 timeout 命令）
_runto() {
  local sec="$1"; shift
  local tmp; tmp=$(mktemp)
  ( "$@" >"$tmp" 2>&1 ) &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$sec" ]; then
      kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      cat "$tmp"; rm -f "$tmp"; return 124
    fi
    sleep 1; waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null
  cat "$tmp"; rm -f "$tmp"
}

R()    { _runto 20 adb -s "$S" shell "$@" | tr -d '\r'; }
die()  { echo "[FAIL] $*"; exit 1; }

connect() {
  [ -z "$IP" ] && die "用法: bash tv_adb.sh ${CMD:-<命令>} <电视IP>"
  _runto 15 adb connect "$S" >/dev/null 2>&1
  sleep 2
  local st
  st=$(_runto 15 adb -s "$S" get-state 2>/dev/null | tr -d '\r')
  if [ "$st" != "device" ]; then
    echo "[FAIL] 未连接到 $S（状态: ${st:-无响应}）"
    echo "  排查:"
    echo "   1) 电视「设置 → 账号与安全 → ADB 调试」是否已开"
    echo "   2) 首次连接需在电视上点「始终允许」授权框"
    echo "   3) 电视与本机是否同一局域网"
    echo "   4) 端口测试: nc -z -G 2 $IP 5555"
    exit 1
  fi
  echo "[OK] 已连接 $S"
}

exists()       { R pm list packages | grep -q "package:$1"; }
# ★ 进程存活判断：老电视 ps -A 无输出，必须用 dumpsys
proc_alive()   { R "dumpsys activity processes" | grep -q "$1"; }
stopped_flag() { R "dumpsys package $1" | grep -oE "stopped=(true|false)" | head -1 | cut -d= -f2; }
cur_focus()    { R "dumpsys window windows" | grep mCurrentFocus | sed 's/.*u0 //'; }
crash_count()  { R 'logcat -d -b crash -t 30' | grep -ci FATAL; }

AD_PKGS=(
  com.miui.systemAdSolution
  com.miui.tv.analytics
  com.xiaomi.statistic
  com.xiaomi.mitv.tvpush.tvpushservice
)

# ========== 子命令 ==========

cmd_probe() {
  connect
  echo
  echo "=== 设备信息 ==="
  echo "  型号     : $(R getprop ro.product.model)"
  echo "  Android  : $(R getprop ro.build.version.release)  (SDK $(R getprop ro.build.version.sdk))"
  echo "  固件     : $(R getprop ro.build.version.incremental)"
  echo "  面板     : $(R getprop ro.boot.mi.panel_resolution)"
  echo "  内存     : $(R 'grep MemTotal /proc/meminfo' | tr -s ' ')"
  echo "  可用内存 : $(R 'grep MemAvailable /proc/meminfo' | tr -s ' ')"
  echo "  存储     : $(R 'df -h /data' | tail -1 | tr -s ' ')"
  echo "  包总数   : $(R pm list packages | wc -l | tr -d ' ')"
  echo
  echo "=== 权限边界探测（决定能用哪些命令）==="
  local tgt o
  tgt=$(R pm list packages | sed 's/package://' | grep -vE '^android|^com\.android' | head -1)
  if [ -n "$tgt" ]; then
    o=$(R "pm disable-user --user 0 $tgt" 2>&1)
    if echo "$o" | grep -q "SecurityException"; then
      echo "  pm disable-user : [不可用] 权限被拒 → 改用 am force-stop"
    elif [ -z "$o" ]; then
      echo "  pm disable-user : [可用]"
      R "pm enable --user 0 $tgt" >/dev/null 2>&1
    else
      echo "  pm disable-user : [未知] $o"
    fi
    o=$(R "am force-stop $tgt" 2>&1)
    if [ -z "$o" ]; then
      echo "  am force-stop   : [可用] ← 唯一推荐手段"
    else
      echo "  am force-stop   : [异常] $o"
    fi
  fi
  echo "  root            : $(R 'which su' 2>&1 | head -1)"
  echo "  /system         : $(R "mount | grep ' /system '" | tr -s ' ' | cut -c1-60)"
  echo
  echo "=== 桌面情况 ==="
  echo "  当前焦点: $(cur_focus)"
  echo "  候选桌面:"
  R pm list packages | sed 's/package://' | grep -iE 'tvhome|launcher|dangbei|emotn|leanch' | sed 's/^/    /'
  echo "  原生桌面特权标记:"
  R "dumpsys package com.mitv.tvhome" 2>/dev/null | grep -oE 'privateFlags=\[[^]]*\]' | head -1 | sed 's/^/    /'
  echo
  echo "=== 内存大户（前 12）==="
  R "dumpsys meminfo" 2>/dev/null | sed -n '/Total PSS by process/,+13p' | tail -12 | sed 's/^/  /'
}

cmd_status() {
  connect
  echo
  echo "=== 桌面状态 ==="
  local f s
  f=$(cur_focus)
  echo "  当前焦点: ${f:-未知}"
  case "$f" in
    *dangbei*)     echo "  → 当贝桌面" ;;
    *tvhome*)      echo "  → 小米原生桌面" ;;
    *screensaver*) echo "  → 待机屏保（正常）" ;;
    "")            echo "  → 焦点未知" ;;
    *)             echo "  → 其他界面" ;;
  esac
  echo "  原生 stopped : $(stopped_flag com.mitv.tvhome)  （false = 正常）"
  echo "  崩溃计数     : $(crash_count)"
  echo "  永久禁用清单 : $(R 'pm list packages -d' | tr '\n' ' ')"
  echo
  echo "=== 广告服务状态 ==="
  printf "  %-36s %s\n" "包名" "状态"
  for p in "${AD_PKGS[@]}" com.xiaomi.mitv.upgrade; do
    if ! exists "$p"; then printf "  %-36s %s\n" "${p##*.}" "未安装"; continue; fi
    s=$(stopped_flag "$p")
    if [ "$s" = "true" ]; then printf "  %-36s %s\n" "${p##*.}" "[已停]"
    else printf "  %-36s %s\n" "${p##*.}" "[运行]"; fi
  done
  echo
  echo "=== 亮度 ==="
  echo "  $(R 'settings get system screen_brightness') / 255"
}

cmd_deadbiz() {
  connect
  echo
  echo "=== 去广告（force-stop）==="
  echo "注意: force-stop 是会话内临时抑制。被系统 bind 的服务包（广告/统计/推送）"
  echo "      会在重启或运行一段时间后被自动拉起，需要时重跑本命令。"
  echo
  local p o
  for p in "${AD_PKGS[@]}"; do
    if ! exists "$p"; then echo "  [跳过] 未安装 ${p##*.}"; continue; fi
    o=$(R am force-stop "$p")
    if [ -z "$o" ]; then echo "  [已停] ${p##*.}"
    else echo "  [ERR ] ${p##*.} -> $o"; fi
  done
  echo
  echo "=== 健康验证 ==="
  sleep 2
  echo "  桌面停止标志: $(stopped_flag com.mitv.tvhome)  （应为 false）"
  echo "  崩溃计数    : $(crash_count)"
}

cmd_install() {
  local apk="${3:-}"
  [ -z "$apk" ] && die "用法: bash tv_adb.sh install <IP> <apk路径>"
  [ -f "$apk" ] || die "APK 不存在: $apk"
  connect
  echo
  echo "=== 校验 APK ==="
  file "$apk" | sed 's/^/  /'
  echo "  SHA256: $(shasum -a 256 "$apk" | cut -d' ' -f1)"
  echo
  echo "=== 推送 ==="
  _runto 300 adb -s "$S" push "$apk" /data/local/tmp/_install.apk 2>&1 | tail -1
  echo
  echo "=== 安装（走 shell 通道，绕过广电合规拦截）==="
  R "pm install -r /data/local/tmp/_install.apk"
  echo
  echo "=== 清理 ==="
  R "rm -f /data/local/tmp/_install.apk"
  echo "  已清理"
}

cmd_launcher() {
  connect
  echo
  echo "=== 桌面候选 ==="
  R pm list packages | sed 's/package://' | grep -iE 'tvhome|launcher|dangbei|emotn' | sed 's/^/  /'
  echo
  echo "=== 当前焦点 ==="
  echo "  $(cur_focus)"
  echo
  echo "=== 为何无法设置系统默认桌面 ==="
  echo "  原生桌面标记: $(R 'dumpsys package com.mitv.tvhome' | grep -oE 'privateFlags=\[[^]]*\]' | head -1)"
  echo
  echo "  原因链:"
  echo "   1) 原生桌面是 PRIVILEGED 特权应用 → HOME 意图永远优先选它"
  echo "   2) Android 6.0 无 pm set-home-activity 命令（Oreo 才加）"
  echo "   3) pm disable/hide 原生桌面 → 权限被拒（缺 MANAGE_USERS）"
  echo "   4) 无 root → 改不了 /data/system 下的 preferred-activities"
  echo
  echo "  可行解:"
  echo "   - 第三方桌面靠自带 HomeKeyEventCatchService 抢 HOME 键"
  echo "   - 关键在【保住它进程存活】，而不是压制原生桌面"
  echo
  echo "  唤起当贝: bash tv_adb.sh keep $IP"
}

cmd_keep() {
  local pkg="${3:-com.dangbei.tvlauncher}"
  local main="${4:-}"
  if [ -z "$main" ]; then
    case "$pkg" in
      com.dangbei.tvlauncher) main="com.dangbei.launcher.ui.main.MainActivity" ;;
      *) main=$(R "dumpsys package $pkg" | grep -A2 'android.intent.action.MAIN' | grep -oE "$pkg/[A-Za-z0-9_.]+" | head -1 | cut -d/ -f2) ;;
    esac
  fi
  connect
  echo
  if proc_alive "$pkg"; then
    echo "  [存活] $pkg 已在运行"
  else
    echo "  [唤起] $pkg 未运行，正在启动..."
    R "am start -n $pkg/$main" >/dev/null 2>&1
    sleep 3
    if proc_alive "$pkg"; then
      echo "  [OK] 已拉起"
    else
      echo "  [WARN] 拉不起来。检查包名与 Activity:"
      echo "     $pkg/$main"
    fi
  fi
  echo
  echo "  当前焦点: $(cur_focus)"
}

cmd_power() {
  connect
  echo
  echo "=== 关机（电源键，等同遥控器）==="
  echo "  注: 彻底关机 ACTION_REQUEST_SHUTDOWN 需 android.permission.SHUTDOWN，"
  echo "      普通 shell 没有权限，只能用电源键。"
  R input keyevent KEYCODE_POWER
  sleep 3
  echo -n "  验证中... "
  local st
  st=$(_runto 10 adb -s "$S" get-state 2>/dev/null | tr -d '\r')
  if [ "$st" = "device" ]; then
    echo "仍在线（可能只是熄屏）"
  else
    echo "[OK] 已断开 → 关机成功"
  fi
}

cmd_brightness() {
  connect
  local val="${3:-}"
  if [ -z "$val" ]; then
    echo "  当前亮度: $(R 'settings get system screen_brightness') / 255"
  else
    case "$val" in *[!0-9]*) die "亮度必须是整数";; esac
    if [ "$val" -lt 0 ] || [ "$val" -gt 255 ]; then
      die "亮度超范围（0-255）"
    fi
    echo "  原值: $(R 'settings get system screen_brightness')"
    R "settings put system screen_brightness $val"
    sleep 1
    echo "  新值: $(R 'settings get system screen_brightness')"
  fi
  echo
  echo "  提示: 对比度/色温/锐度/降噪等画质参数不在 Android 层，"
  echo "        由芯片 tvserver 的 PQ 模块管理，adb 读不到也改不了，"
  echo "        必须用遥控器在电视「设置 → 图像与声音」里调。"
}

cmd_restore() {
  connect
  echo
  echo "=== 恢复被停用的服务 ==="
  local p s svc
  for p in "${AD_PKGS[@]}"; do
    exists "$p" || continue
    s=$(stopped_flag "$p")
    if [ "$s" != "true" ]; then
      echo "  [跳过] ${p##*.} 未被停"
      continue
    fi
    svc=$(R "dumpsys package $p" | grep -oE "$p/[A-Za-z0-9_.\$]*Service" | head -1 | cut -d/ -f2)
    if [ -n "$svc" ]; then
      R "am startservice -n $p/$svc" >/dev/null 2>&1
      sleep 1
    fi
    if [ "$(stopped_flag "$p")" = "false" ]; then
      echo "  [已恢复] ${p##*.}"
    else
      echo "  [需手动] ${p##*.} — 在电视上打开该应用一次即可"
    fi
  done
}

# ========== 入口 ==========

case "$CMD" in
  probe)      cmd_probe ;;
  status)     cmd_status ;;
  deadbiz)    cmd_deadbiz ;;
  install)    cmd_install ;;
  launcher)   cmd_launcher ;;
  keep)       cmd_keep ;;
  power)      cmd_power ;;
  brightness) cmd_brightness ;;
  restore)    cmd_restore ;;
  *)
    cat <<'USAGE'
安卓电视 ADB 远程工具箱

用法: bash tv_adb.sh <命令> <电视IP> [参数]

  probe      <IP>              体检（机型/权限边界/桌面/内存）★首次必跑
  status     <IP>              状态查看
  deadbiz    <IP>              去广告
  install    <IP> <apk路径>    安装 APK（绕过广电合规拦截）
  launcher   <IP>              桌面管理（含特权分析）
  keep       <IP> [包名]       桌面保活（唤起指定桌面，默认当贝）
  power      <IP>              关机
  brightness <IP> [0-255]      读取/设置亮度
  restore    <IP>              恢复被停用的服务

依赖 adb（platform-tools）。未安装时：
  mkdir -p ~/tools/android && cd ~/tools/android && \
  curl -L -o pt.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip && \
  unzip -q pt.zip
USAGE
    ;;
esac
