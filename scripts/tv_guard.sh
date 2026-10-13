#!/bin/bash
# 电视桌面保活守护（配合 tv_adb.sh 使用）
#
# 解决的问题：第三方桌面（如当贝）与系统原生桌面争抢 HOME 键。
#            原生桌面通常是 PRIVILEGED 特权应用，系统 HOME 意图永远优先选它，
#            无 root 无法翻转。第三方桌面只能靠自带的 HomeKeyEventCatchService 抢。
#
# ★ 核心策略：**保活第三方桌面，而不是压制原生桌面**
#   实测依据（MiTV4-ANSM0）：
#     - 当贝进程存活时，按 HOME 直接进当贝，耗时 0.15-0.26 秒
#     - 当贝被内存回收后，按 HOME 先落到原生桌面，再切当贝（0.3-2.2 秒，跳两次）
#     - force-stop 原生桌面反而让系统重新 bind 它，拖慢响应 → 错误方向
#
# 用法:
#   bash tv_guard.sh check  <IP>   跑一轮检查（定时调用）
#   bash tv_guard.sh force  <IP>   立即唤起桌面
#   bash tv_guard.sh status <IP>   查看状态
#   bash tv_guard.sh pause <IP>    暂停（当前版本 pause 只是提示）
#
# 定时执行（二选一，均需用户在终端自行安装）:
#   launchd（推荐，无需 sudo）:
#     见 SKILL.md「定时执行」章节的 plist 模板
#   cron（需先 sudo launchctl load -w /System/Library/LaunchDaemons/com.vix.cron.plist）:
#     * * * * * /bin/bash <本脚本路径> check <IP> >> /tmp/tvguard.log 2>&1
#
# 设计要点（全部实测所得，勿改）:
#   1. macOS 无 timeout → 后台作业 + 轮询
#   2. macOS 无 flock → mkdir 原子锁 + PID 自愈
#   3. 老电视 ps -A 只输出表头 → 用 dumpsys activity processes
#   4. 安全闸：目标桌面不可用时，绝不动手（避免两个桌面都没有 → 黑屏）

set -uo pipefail

CMD="${1:-check}"
IP="${2:-}"
S="${IP}:5555"

# 要保活的桌面（按需修改）
KEEP_PKG="${KEEP_PKG:-com.dangbei.tvlauncher}"
KEEP_MAIN="${KEEP_MAIN:-com.dangbei.launcher.ui.main.MainActivity}"

LOCK="${TMPDIR:-/tmp}/tv_guard.lock"
LOG="${TMPDIR:-/tmp}/tvguard.log"
ADB_DIR="$HOME/tools/android/platform-tools"
[ -x "$ADB_DIR/adb" ] && export PATH="$ADB_DIR:$PATH"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null; }

# ---------- 超时执行（macOS 无 timeout）----------
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

R() { _runto 20 adb -s "$S" shell "$@" | tr -d '\r'; }

# ---------- 单实例锁（mkdir 原子 + PID 自愈）----------
# 上次异常退出会留下死锁，靠 PID 存活检查自动清理
if ! mkdir "$LOCK" 2>/dev/null; then
  lock_pid=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
    rmdir "$LOCK" 2>/dev/null
  else
    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
    [ "$lock_age" -le 120 ] && exit 0
    rmdir "$LOCK" 2>/dev/null
  fi
  mkdir "$LOCK" 2>/dev/null || exit 0
fi
echo $$ > "$LOCK/pid" 2>/dev/null
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# ---------- 连接 ----------
connected() {
  [ "$( _runto 15 adb -s "$S" get-state 2>/dev/null | tr -d '\r')" = "device" ] && return 0
  _runto 15 adb connect "$S" >/dev/null 2>&1
  sleep 2
  [ "$( _runto 15 adb -s "$S" get-state 2>/dev/null | tr -d '\r')" = "device" ]
}

# ★ 进程存活：老电视 ps -A 无输出，必须用 dumpsys
proc_alive() { R "dumpsys activity processes" | grep -q "$1"; }
cur_focus()  { R "dumpsys window windows" | grep mCurrentFocus | sed 's/.*u0 //' | cut -d/ -f1; }

do_check() {
  connected || { log "SKIP 设备不可达"; return 0; }

  # ★ 安全闸：目标桌面不可用 → 绝不触发任何切换动作
  if ! proc_alive "$KEEP_PKG"; then
    _runto 20 adb -s "$S" shell "am start -n $KEEP_PKG/$KEEP_MAIN" >/dev/null 2>&1
    sleep 3
    if ! proc_alive "$KEEP_PKG"; then
      log "SKIP $KEEP_PKG 拉不起来 → 保持现状不动"
      return 0
    fi
    log "KEEP 已唤起 $KEEP_PKG"
    return 0
  fi

  # 已存活 → 仅当它不在前台时唤起（不碰原生桌面）
  focus=$(cur_focus)
  case "$focus" in
    "$KEEP_PKG")
      : ;;   # 已在前台，不打扰
    *)
      _runto 20 adb -s "$S" shell "am start -n $KEEP_PKG/$KEEP_MAIN" >/dev/null 2>&1
      log "KEEP 已唤起 $KEEP_PKG（当前前台: ${focus:-未知}）"
      ;;
  esac
  return 0
}

case "$CMD" in
  check)  do_check ;;
  force)
    connected || { echo "[FAIL] 设备不可达"; exit 1; }
    R "am start -n $KEEP_PKG/$KEEP_MAIN" >/dev/null 2>&1
    sleep 2
    echo "已唤起。当前焦点: $(cur_focus)"
    ;;
  status)
    connected || { echo "[FAIL] 设备不可达"; exit 1; }
    echo "设备    : $(R getprop ro.product.model)"
    echo "当前焦点: $(cur_focus)"
    if proc_alive "$KEEP_PKG"; then echo "保活目标: $KEEP_PKG 运行中"
    else echo "保活目标: $KEEP_PKG 未运行"; fi
    echo "最近日志:"
    tail -5 "$LOG" 2>/dev/null | sed 's/^/  /'
    ;;
  pause)
    echo "已暂停本次调用。（如需长期停用，请卸载定时任务）"
    ;;
  *)
    echo "用法: bash tv_guard.sh [check|force|status|pause] <电视IP>"
    echo "  环境变量可覆盖保活目标: KEEP_PKG / KEEP_MAIN"
    ;;
esac
