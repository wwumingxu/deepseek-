#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# DSH Linux 迁移安装脚本
#
# 把本仓库 profile/ 下的 Windows 端 DeepSeek Harness 插件与设置，
# 安装到当前 Linux 机器上的 DSH profile 里。
#
#   用法:  bash install.sh [选项]
#   选项:
#     --profile <name>  目标 profile（默认 web；桌面版用 desktop）
#     --dsh-home <dir>  DSH 家目录（默认 $DSH_HOME 或 ~/.dsh）
#     --no-install      只写入配置文件，不执行插件安装
#     --dry-run         只打印将要执行的操作
#     --yes, -y         跳过确认提示
#     --force           目标 profile 已存在时也直接覆盖（默认会先备份）
#     -h, --help        显示帮助
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/profile"

PROFILE="web"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
DO_INSTALL=1
DRY_RUN=0
ASSUME_YES=0
FORCE=0

# ------------------------------ 输出工具 -----------------------------------
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[36m'
else
  C_RESET=''; C_BOLD=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BLUE=''
fi

step() { printf '\n%s==> %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
ok()   { printf '%s  ✔ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '%s  ! %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
die()  { printf '%s  ✘ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }

usage() { sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

# ------------------------------ 参数解析 -----------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)    PROFILE="${2:?--profile 需要一个值}"; shift 2 ;;
    --dsh-home)   DSH_HOME="${2:?--dsh-home 需要一个值}"; shift 2 ;;
    --no-install) DO_INSTALL=0; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --yes|-y)     ASSUME_YES=1; shift ;;
    --force)      FORCE=1; shift ;;
    -h|--help)    usage ;;
    *)            die "未知参数: $1（用 --help 查看用法）" ;;
  esac
done

PROFILE_DIR="$DSH_HOME/profiles/$PROFILE"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$PROFILE_DIR/.migration-backup-$STAMP"

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

# ------------------------------ 环境检查 -----------------------------------
step "检查环境"

[ -d "$SRC_DIR" ] || die "找不到 $SRC_DIR，请在仓库根目录运行本脚本。"

DSH_BIN="$(command -v dsh || true)"
if [ -n "$DSH_BIN" ]; then
  ok "dsh: $DSH_BIN ($("$DSH_BIN" --version 2>/dev/null | head -n1 || echo '版本未知'))"
else
  if [ "$DO_INSTALL" = 1 ]; then
    warn "PATH 中没有 dsh 命令，将无法自动安装插件。"
    warn "可先安装：npm install -g @deepseek-ai/dsh   （需要 Node.js >= 24.9）"
    warn "或用 --no-install 只写入配置，稍后手动安装。"
  else
    warn "PATH 中没有 dsh 命令（--no-install 模式，跳过检查）"
  fi
fi

if command -v node >/dev/null 2>&1; then
  NODE_VER="$(node -v 2>/dev/null || echo v0)"
  NODE_MAJOR="$(printf '%s' "$NODE_VER" | sed 's/^v//' | cut -d. -f1)"
  if [ "${NODE_MAJOR:-0}" -lt 24 ] 2>/dev/null; then
    warn "Node 版本为 $NODE_VER，DSH 要求 >= 24.9.0；插件安装可能失败。"
  else
    ok "node: $NODE_VER"
  fi
else
  warn "未检测到 node，若 dsh 已安装可忽略。"
fi

if command -v pnpm >/dev/null 2>&1; then
  ok "pnpm: $(pnpm --version 2>/dev/null || echo '版本未知')"
else
  warn "未检测到 pnpm；dsh plugin 需要一个可用的 pnpm。"
  warn "可执行：npm install -g pnpm   或   corepack enable"
fi

if [ "$PROFILE" = "desktop" ]; then
  warn "desktop 是 DSH 桌面版保留的 profile，必须由桌面版应用初始化后才能安装插件。"
  if [ ! -f "$PROFILE_DIR/package.json" ]; then
    die "找不到 $PROFILE_DIR/package.json：请先启动一次 Linux 版 DSH 桌面版，再完全退出后重试。"
  fi
fi

# ------------------------------ 计划确认 -----------------------------------
step "安装计划"
printf '  DSH_HOME    : %s\n' "$DSH_HOME"
printf '  目标 profile: %s  ->  %s\n' "$PROFILE" "$PROFILE_DIR"
printf '  配置来源    : %s\n' "$SRC_DIR"
printf '  备份目录    : %s\n' "$BACKUP_DIR"
printf '  安装插件    : %s\n' "$([ "$DO_INSTALL" = 1 ] && echo '是（dsh plugin install）' || echo '否（--no-install）')"

if [ "$DRY_RUN" = 0 ] && [ "$ASSUME_YES" = 0 ]; then
  printf '\n继续执行？[y/N] '
  read -r ANSWER || ANSWER=""
  case "$ANSWER" in
    y|Y|yes|YES) ;;
    *) die "已取消。" ;;
  esac
fi

if [ "$DRY_RUN" = 1 ]; then
  ok "dry-run 模式：不会修改任何文件"
fi

# ------------------------------ 备份 ---------------------------------------
step "备份现有配置"
if [ -d "$PROFILE_DIR" ]; then
  run mkdir -p "$BACKUP_DIR"
  for f in package.json pnpm-lock.yaml pnpm-workspace.yaml cordis.yml cordis.patch.yml; do
    if [ -f "$PROFILE_DIR/$f" ]; then
      run cp -a "$PROFILE_DIR/$f" "$BACKUP_DIR/$f"
      ok "已备份 $f"
    fi
  done
else
  run mkdir -p "$PROFILE_DIR"
  ok "新建 profile 目录：$PROFILE_DIR"
fi

# ------------------------------ 写入配置 -----------------------------------
step "写入配置"
for f in package.json cordis.yml cordis.patch.yml pnpm-workspace.yaml; do
  [ -f "$SRC_DIR/$f" ] || die "仓库缺少 profile/$f"
  run cp "$SRC_DIR/$f" "$PROFILE_DIR/$f"
  ok "写入 $f"
done

# profile 名与目录保持一致（仅影响 package.json 的 name 字段）
if [ "$DRY_RUN" = 0 ]; then
  sed -i "s/\"dsh-profile-linux\"/\"dsh-profile-$PROFILE\"/" "$PROFILE_DIR/package.json"
fi

# Windows 的 lockfile 与本次依赖列表不一致，删除后由 pnpm 重新解析
if [ -f "$PROFILE_DIR/pnpm-lock.yaml" ]; then
  run rm -f "$PROFILE_DIR/pnpm-lock.yaml"
  ok "移除旧的 pnpm-lock.yaml（已备份），由 pnpm 重新生成"
fi

# ------------------------------ 安装依赖 -----------------------------------
step "安装插件依赖"
if [ "$DO_INSTALL" = 1 ] && [ -n "$DSH_BIN" ]; then
  if ! run "$DSH_BIN" plugin --profile "$PROFILE" install; then
    warn "插件安装失败。"
    if [ "$PROFILE" = "desktop" ]; then
      warn "请完全退出 DSH 桌面版后，用桌面版自带的 dsh 命令重试，或在桌面版插件页手动安装。"
    fi
    warn "常见原因见 docs/TROUBLESHOOTING.md；配置文件已写入，可修复后重试："
    warn "  dsh plugin --profile $PROFILE install"
    exit 1
  fi
  ok "插件安装完成"
else
  warn "已跳过插件安装。稍后请执行：dsh plugin --profile $PROFILE install"
fi

# ------------------------------ 校验 ---------------------------------------
step "校验配置"
if [ -n "$DSH_BIN" ] && [ "$DRY_RUN" = 0 ]; then
  if "$DSH_BIN" --profile "$PROFILE" --dump-config >/dev/null 2>"$PROFILE_DIR/.dump-config.err"; then
    ok "配置树组合成功（dsh --dump-config 通过）"
    rm -f "$PROFILE_DIR/.dump-config.err"
  else
    warn "配置校验失败，错误输出如下："
    cat "$PROFILE_DIR/.dump-config.err" >&2 || true
    warn "可用 rollback.sh 还原到安装前的配置。"
    exit 1
  fi
else
  warn "已跳过校验。"
fi

# ------------------------------ 完成 ---------------------------------------
step "完成"
cat <<EOF
  profile 已就绪：$PROFILE

  下一步：
    1. 启动：            dsh web                （或 dsh --profile $PROFILE）
    2. 登录 DeepSeek：   在 Web 界面里用设备码登录（deepseek-account）
    3. 设置 GPT 中转 key（可选，llm-pi-ai 的 gpt provider 用）：
         export GPT_API_KEY=sk-xxxx
       然后重启 dsh（该 provider 通过环境变量读取密钥）
    4. 打开设置 → 插件，确认 12 个插件均已启用

  回滚：  bash rollback.sh --profile $PROFILE
  备份：  $BACKUP_DIR
EOF
