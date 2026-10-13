#!/bin/bash
# 远程电视优化脚本（去广告/ 桌面管理 / 状态体检）
#
# 设计要点（均来自实战踩坑，勿删）：
#  1. 所有操作前校验包名真实存在 —— 防止 pm disable 静默失败
#  2. 只用 am force-stop —— pm disable-user/hide 在老机型上会被权限拒
#  3. 每个动作后验证健康状态 —— 桌面焦点 + crashed 计数
#  4. 所有 adb shell 输出接 tr -d '\r' —— Windows 行尾会破坏字符串比对
#
# 用法:
#   bash tv_adb.sh probe    <IP>   # 体检：机型/权限边界/桌面健康
#   bash tv_adb.sh deadbiz <IP>   # 去广告（force-stop 广告与冗余服务）
#   bash tv_adb.sh status   <IP>   # 状态 + 健康检查
#   bash tv_adb.sh restore  <IP>   # 恢复被停的服务
#   bash tv_adb.sh launcher <IP>   # 桌面管理

set -uo pipefail

IP="${2:-}"
ADB_DIR="$HOME/tools/android/platform-tools"
[ -x "$ADB_DIR/adb" ] && export PATH="$ADB_DIR:$PATH"

S="$IP:5555"
run()   { adb -s "$S" shell "$@" 2>&1 | tr -d '\r'; }
state() { adb -s "$S" get-state 2>&1 | tr -d '\r'; }

# 桌面健康：焦点窗口 + 崩溃计数
check_health() {
  local f c
  f=$(run "dumpsys window windows" | grep mCurrentFocus | head -1)
  c=$(run "logcat -d -b crash -t 30" | grep -ci 'FATAL')
  case "$f" in
    *tvhome*)    local d="原生桌面" ;;
    *dangbei*)   local d="当贝桌面" ;;
    *emotn*)     local d="Emotn 桌面" ;;
    *screensaver*) local d="待机屏保（正常，非异常）" ;;
    "")          local d="焦点未知" ;;
    *)           local d="其他界面" ;;
  esac
  echo "  焦点: ${f:-无}"
  echo "  判定: $d"
  echo "  崩溃计数: $c$([ "$c" -gt 0 ] && echo '  ← 异常！需排查')"
}

connect() {
  [ -z "$IP" ] && { echo "[FAIL] 用法: bash $0 <子命令> <电视IP>"; exit 1; }
  adb connect "$S" >/dev/null 2>&1
  sleep 1
  if [ "$(state)" != "device" ]; then
    echo "[FAIL] 未连接到 $S"
    echo "  检查: 1) 电视 ADB 调试已开（设置→账号与安全→ADB 调试）"
    echo "        2) 电视与本机同局域网  3) 首次连接需在电视上点「始终允许」"
    exit 1
  fi
  echo "[OK] 已连接 $S"
}

exists()       { run pm list packages | grep -q "package:$1"; }
stopped_flag() { run "dumpsys package $1" | grep -oE "stopped=(true|false)" | head -1 | cut -d= -f2; }

case "${1:-}" in

probe)
  connect
  echo
  echo "=== 设备信息 ==="
  echo "  型号: $(run getprop ro.product.model)"
  echo "  Android: $(run getprop ro.build.version.release)  SDK: $(run getprop ro.build.version.sdk)"
  echo "  固件: $(run getprop ro.build.version.incremental)"
  echo "  内存: $(run 'grep MemTotal /proc/meminfo' | tr -s ' ')"
  echo "  存储: $(run 'df -h /data' | tail -1 | tr -s ' ')"
  echo "  包总数: $(run pm list packages | wc -l | tr -d ' ')"
  echo
  echo "=== 权限边界探测（决定用什么命令）==="
  local_first=$(run pm list packages | head -1 | tr -d '\r')
  tgt=$(run pm list packages | sed 's/package://' | grep -vE "^android|^com.android" | head -1)
  echo "  测试包: ${tgt:-N/A}"
  o=$(run "pm disable-user --user 0 $tgt" 2>&1)
  if echo "$o" | grep -q "SecurityException"; then
    echo "  pm disable-user : [不可用] 权限被拒 → 用 force-stop"
  elif [ -z "$o" ]; then
    echo "  pm disable-user : [可用]"
    run "pm enable --user 0 $tgt" >/dev/null 2>&1
  else
    echo "  pm disable-user : [未知] $o"
  fi
  o=$(run "am force-stop $tgt" 2>&1)
  [ -z "$o" ] && echo "  am force-stop  : [可用] ← 唯一推荐手段" || echo "  am force-stop  : [异常] $o"
  echo "  root: $(run 'which su' 2>&1 | head -1)"
  echo "  /system: $(run "mount | grep ' /system '" | tr -s ' ')"
  echo
  echo "=== 桌面健康 ==="
  check_health
  echo
  echo "=== 候选桌面包名（供人工确认）==="
  run pm list packages | sed 's/package://' | grep -iE "tvhome|launcher|dangbei|emotn|leanch|atv"
  ;;

deadbiz)
  connect
  echo
  echo "=== 去广告：停用广告与冗余服务 ==="
  echo "注意: force-stop 只是临时抑制 —— 被系统 bind 的服务包重启后会自动复活，需配 startup 做开机自启"
  echo
  # 格式: 包名|说明  —— bash 数组必须用 IFS 解析，不能用 ${item%%|*|（bash 3.2 错位）
  LIST=(
    "com.miui.systemAdSolution|系统广告服务（开机/桌面广告核心）"
    "com.miui.tv.analytics|系统埋点统计"
    "com.xiaomi.statistic|小米统计上报"
    "com.xiaomi.mitv.tvpush.tvpushservice|电视推送（停后桌面推荐位可能不刷新）"
    "com.xiaomi.gamecenter.sdk.service.mibox|游戏中心"
    "com.xiaomi.mimusic2|小米音乐（不影响系统媒体框架）"
    "com.mitv.screensaver|屏保"
  )
  for item in "${LIST[@]}"; do
    IFS="|" read -r p desc <<< "$item"
    if ! exists "$p"; then
      echo "  [跳过] 未安装 ${p##*.}"
      continue
    fi
    out=$(run am force-stop "$p")
    if [ -z "$out" ]; then
      echo "  [已停] ${p##*.}  ($desc)"
    else
      echo "  [ERR ] ${p##*.} -> $out"
    fi
  done
  echo
  echo "=== 桌面健康验证 ==="
  sleep 2
  check_health
  echo
  echo ">>> 立即生效。若要开机自动生效见 SKILL.md 的 startup 说明"
  ;;

status)
  connect
  echo
  echo "=== 桌面健康 ==="
  check_health
  echo
  echo "=== 广告服务状态 ==="
  printf "  %-26s %-10s %s\n" "包名" "状态" "说明"
  printf "  %-26s %-10s %s\n" "--------------------------" "----------" "----"
  LIST=(
    "com.miui.systemAdSolution|开机/桌面广告"
    "com.miui.tv.analytics|埋点统计"
    "com.xiaomi.statistic|统计上报"
    "com.xiaomi.mitv.tvpush.tvpushservice|推送服务"
    "com.xiaomi.gamecenter.sdk.service.mibox|游戏中心"
    "com.xiaomi.mimusic2|小米音乐"
  )
  for item in "${LIST[@]}"; do
    IFS="|" read -r p desc <<< "$item"
    if ! exists "$p"; then
      printf "  %-26s %-10s %s\n" "${p##*.}" "未装" "$desc"; continue
    fi
    if [ "$(stopped_flag "$p")" = "true" ]; then m="[已停]"; else m="[运行]"; fi
    printf "  %-26s %-10s %s\n" "${p##*.}" "$m" "$desc"
  done
  echo
  echo "=== 桌面应用安装情况 ==="
  run pm list packages | sed 's/package://' | grep -iE "tvhome|launcher|dangbei|emotn"
  ;;

restore)
  connect
  echo
  echo "=== 恢复被停的服务 ==="
  echo "方式: 显式启动 service 清除 stopped 标志（不删数据、不改系统）"
  echo
  LIST=(
    "com.miui.systemAdSolution|"
    "com.miui.tv.analytics|"
    "com.xiaomi.statistic|"
    "com.xiaomi.mitv.tvpush.tvpushservice|"
    "com.xiaomi.gamecenter.sdk.service.mibox|"
    "com.xiaomi.mimusic2|"
  )
  for item in "${LIST[@]}"; do
    IFS="|" read -r p _ <<< "$item"
    exists "$p" || continue
    if [ "$(stopped_flag "$p")" != "true" ]; then
      echo "  [跳过] ${p##*.} 未被停"; continue
    fi
    svc=$(run "dumpsys package $p" | grep -oE "$p/[A-Za-z0-9_.$]*Service" | head -1)
    if [ -n "$svc" ]; then
      run am startservice -n "$svc" >/dev/null 2>&1
    fi
    sleep 1
    if [ "$(stopped_flag "$p")" = "false" ]; then
      echo "  [已恢复] ${p##*.}"
    else
      echo "  [需手动] ${p##*.} —— 在电视上打开该应用一次即恢复"
    fi
  done
  echo
  echo ">>> 显示[需手动]的，在电视桌面找到该应用点开一次即可。"
  echo ">>> 兜底: 设置 → 系统 → 恢复出厂设置（会清数据，慎用）"
  ;;

launcher)
  connect
  echo
  echo "=== 桌面应用 ==="
  run pm list packages | sed 's/package://' | grep -iE "tvhome|launcher|dangbei|emotn"
  echo
  echo "=== 当前桌面 ==="
  check_health
  echo
  echo "=== 可用操作 ==="
  echo "  切回小米原生桌面:"
  echo "    adb -s $S shell am start -n com.mitv.tvhome/com.mitv.tvhome.MainActivityUserMode"
  echo
  echo "  彻底卸载第三方桌面（-k 保留数据）:"
  echo "    adb -s $S shell pm uninstall -k --user 0 <桌面包名>"
  echo
  echo "  说明: Android 6.0 无 pm set-home-activity 命令（Oreo 才加）"
  echo "        多数桌面靠 BootReceiver + HomeKeyEventCatchService 自抢占"
  ;;

*)
  echo "用法: bash $0 <子命令> <电视IP>"
  echo
  echo "  probe    <IP>   体检：机型/权限边界/桌面健康（首次必跑）"
  echo "  deadbiz <IP>   去广告（force-stop 广告与冗余服务）"
  echo "  status   <IP>   状态 + 健康检查"
  echo "  restore  <IP>   恢复被停的服务"
  echo "  launcher <IP>   桌面管理"
  ;;
esac