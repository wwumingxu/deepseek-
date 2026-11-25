#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# DSH Linux 迁移回滚脚本
#
# 把 install.sh 备份的 profile 配置还原回去，并重新安装依赖。
#
#   用法:  bash rollback.sh [选项]
#   选项:
#     --profile <name>      目标 profile（默认 web）
#     --dsh-home <dir>      DSH 家目录（默认 $DSH_HOME 或 ~/.dsh）
#     --backup <dir-name>   指定备份目录名（默认最近一次）
#     --list                列出所有可用备份
#     -h, --help            显示帮助
# ---------------------------------------------------------------------------
set -euo pipefail

PROFILE="web"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
WANT_BACKUP=""
LIST_ONLY=0

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

usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)  PROFILE="${2:?--profile 需要一个值}"; shift 2 ;;
    --dsh-home) DSH_HOME="${2:?--dsh-home 需要一个值}"; shift 2 ;;
    --backup)   WANT_BACKUP="${2:?--backup 需要一个值}"; shift 2 ;;
    --list)     LIST_ONLY=1; shift ;;
    -h|--help)  usage ;;
    *) die "未知参数: $1（用 --help 查看用法）" ;;
  esac
done

PROFILE_DIR="$DSH_HOME/profiles/$PROFILE"

if [ ! -d "$PROFILE_DIR" ]; then
  die "profile 目录不存在：$PROFILE_DIR"
fi

mapfile -t BACKUPS < <(find "$PROFILE_DIR" -maxdepth 1 -type d -name '.migration-backup-*' | sort)
if [ "${#BACKUPS[@]}" -eq 0 ]; then
  die "没有找到备份（$PROFILE_DIR/.migration-backup-*），无法回滚。"
fi

if [ "$LIST_ONLY" = 1 ]; then
  step "可用备份"
  for b in "${BACKUPS[@]}"; do
    printf '  %s\n' "$(basename "$b")"
  done
  exit 0
fi

if [ -n "$WANT_BACKUP" ]; then
  TARGET="$PROFILE_DIR/$WANT_BACKUP"
  [ -d "$TARGET" ] || die "指定的备份不存在：$TARGET"
else
  TARGET="${BACKUPS[${#BACKUPS[@]}-1]}"
fi

step "回滚 profile: $PROFILE"
printf '  使用备份: %s\n' "$(basename "$TARGET")"

for f in package.json cordis.yml cordis.patch.yml pnpm-workspace.yaml; do
  if [ -f "$TARGET/$f" ]; then
    cp -a "$TARGET/$f" "$PROFILE_DIR/$f"
    ok "还原 $f"
  fi
done

# 备份里没有的配置文件，说明安装前不存在，直接删除
for f in package.json cordis.yml cordis.patch.yml pnpm-workspace.yaml; do
  if [ ! -f "$TARGET/$f" ] && [ -f "$PROFILE_DIR/$f" ]; then
    rm -f "$PROFILE_DIR/$f"
    ok "删除安装时新增的 $f"
  fi
done

# lockfile 中的依赖已变化，重新生成
if [ -f "$TARGET/pnpm-lock.yaml" ]; then
  cp -a "$TARGET/pnpm-lock.yaml" "$PROFILE_DIR/pnpm-lock.yaml"
  ok "还原 pnpm-lock.yaml"
else
  rm -f "$PROFILE_DIR/pnpm-lock.yaml"
fi

step "重新安装依赖"
if command -v dsh >/dev/null 2>&1; then
  dsh plugin --profile "$PROFILE" install || {
    warn "依赖重装失败，请手动执行：dsh plugin --profile $PROFILE install"
    exit 1
  }
  ok "回滚完成"
else
  warn "未找到 dsh 命令，请手动执行：dsh plugin --profile $PROFILE install"
fi
