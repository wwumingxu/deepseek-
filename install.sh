#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# DSH Linux 迁移安装脚本
#
# 把本仓库 profile/ 下的 Windows 端 DeepSeek Harness 插件与设置，
# 安装到当前 Linux 机器上的 DSH profile 里。
#
#   用法:  bash install.sh [选项]
#   选项:
#     --profile <name>  目标 profile（默认自动检测：有 desktop 就装 desktop，否则 web）
#     --dsh-home <dir>  DSH 家目录（默认 $DSH_HOME 或 ~/.dsh）
#     --no-install      只写入配置文件，不执行插件安装
#     --dry-run         只打印将要执行的操作
#     --yes, -y         跳过确认提示
#     --force           目标 profile 已存在时也直接覆盖（默认会先备份）
#     -h, --help        显示帮助
#
#   安装方式按可用性自动选择：
#     1) dsh plugin --profile <name> install   （有 dsh 命令时）
#     2) pnpm install                           （没有 dsh 命令、或 dsh 拒绝管理该 profile 时）
#   两者都没有则直接报错退出，绝不会「跳过安装却显示成功」。
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/profile"

PROFILE=""
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
DO_INSTALL=1
DRY_RUN=0
ASSUME_YES=0
FORCE=0
PROFILE_AUTO=0

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

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

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

# ------------------------------ 工具函数 -----------------------------------
# 找一个可用的 dsh：优先 PATH，其次桌面版自带的 CLI
find_dsh() {
  if command -v dsh >/dev/null 2>&1; then
    command -v dsh
    return 0
  fi
  local f
  for base in /opt /usr/lib /usr/share /usr/local /tmp "$HOME/.local/share" "$HOME/Applications"; do
    [ -d "$base" ] || continue
    f="$(find "$base" -maxdepth 7 -path '*resources/runtime/cli/bin/dsh' -type f 2>/dev/null | head -n1 || true)"
    if [ -n "$f" ]; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

# ------------------------------ 目标 profile -------------------------------
if [ -z "$PROFILE" ]; then
  PROFILE_AUTO=1
  if [ -f "$DSH_HOME/profiles/desktop/package.json" ]; then
    PROFILE="desktop"
  else
    PROFILE="web"
  fi
fi

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

DSH_BIN="$(find_dsh || true)"
if [ -n "$DSH_BIN" ]; then
  ok "dsh: $DSH_BIN ($("$DSH_BIN" --version 2>/dev/null | head -n1 || echo '版本未知'))"
else
  warn "没有找到 dsh 命令（PATH 里没有，也没找到桌面版自带 CLI）。"
fi

NODE_BIN="$(command -v node || true)"
if [ -n "$NODE_BIN" ]; then
  NODE_VER="$("$NODE_BIN" -v 2>/dev/null || echo v0)"
  NODE_MAJOR="$(printf '%s' "$NODE_VER" | sed 's/^v//' | cut -d. -f1)"
  if [ "${NODE_MAJOR:-0}" -lt 24 ] 2>/dev/null; then
    warn "Node 版本为 $NODE_VER，DSH 要求 >= 24.9.0；插件安装可能失败。"
  else
    ok "node: $NODE_VER"
  fi
else
  warn "未检测到 node；若用的是桌面版自带运行时，可忽略。"
fi

PNPM_BIN="$(command -v pnpm || true)"
if [ -n "$PNPM_BIN" ]; then
  ok "pnpm: $("$PNPM_BIN" --version 2>/dev/null || echo '版本未知')"
else
  warn "未检测到 pnpm。"
fi

if [ "$DO_INSTALL" = 1 ] && [ -z "$DSH_BIN" ] && [ -z "$PNPM_BIN" ]; then
  die "无法安装插件：既没有 dsh 命令，也没有 pnpm。
     二选一装好再重试：
       1) npm install -g @deepseek-ai/dsh   （推荐，需 Node >= 24.9）
       2) npm install -g pnpm
     或先只用 --no-install 写配置。"
fi

if [ "$PROFILE" = "desktop" ] && [ ! -f "$PROFILE_DIR/package.json" ]; then
  die "找不到 $PROFILE_DIR/package.json。
     desktop 是桌面版保留 profile，请先启动一次 Linux 版 DSH 桌面版并完全退出，再重试；
     或显式指定 --profile web 安装到命令行 profile。"
fi

# ------------------------------ 计划确认 -----------------------------------
step "安装计划"
printf '  DSH_HOME    : %s\n' "$DSH_HOME"
printf '  目标 profile: %s  ->  %s\n' "$PROFILE" "$PROFILE_DIR"
if [ "$PROFILE_AUTO" = 1 ]; then
  printf '  （自动检测：本机存在 desktop profile 时优先装 desktop）\n'
fi
printf '  配置来源    : %s\n' "$SRC_DIR"
printf '  备份目录    : %s\n' "$BACKUP_DIR"
if [ "$DO_INSTALL" = 1 ]; then
  if [ -n "$DSH_BIN" ]; then
    printf '  安装方式    : dsh plugin --profile %s install（失败则退回 pnpm）\n' "$PROFILE"
  else
    printf '  安装方式    : 直接 pnpm install（未找到 dsh 命令）\n'
  fi
else
  printf '  安装方式    : 不安装（--no-install）\n'
fi

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

# Windows 的 lockfile 与本次依赖列表不一致，删除后重新解析
if [ -f "$PROFILE_DIR/pnpm-lock.yaml" ]; then
  run rm -f "$PROFILE_DIR/pnpm-lock.yaml"
  ok "移除旧的 pnpm-lock.yaml（已备份），由 pnpm 重新生成"
fi

# ------------------------------ 安装依赖 -----------------------------------
step "安装插件依赖"
INSTALLED=0
if [ "$DO_INSTALL" = 1 ]; then
  if [ "$DRY_RUN" = 1 ]; then
    if [ -n "$DSH_BIN" ]; then
      printf '  [dry-run] %s plugin --profile %s install\n' "$DSH_BIN" "$PROFILE"
    fi
    printf '  [dry-run] (cd %s && pnpm install)\n' "$PROFILE_DIR"
    INSTALLED=1
  else
    if [ -n "$DSH_BIN" ]; then
      if "$DSH_BIN" plugin --profile "$PROFILE" install; then
        INSTALLED=1
      else
        warn "dsh plugin install 失败（桌面版 profile 常被拒绝管理，或 CLI 版本不兼容）"
        if [ -n "$PNPM_BIN" ]; then
          warn "改用 pnpm 直接安装到 $PROFILE_DIR …"
        fi
      fi
    fi
    if [ "$INSTALLED" = 0 ] && [ -n "$PNPM_BIN" ]; then
      if ( cd "$PROFILE_DIR" && "$PNPM_BIN" install ); then
        INSTALLED=1
      fi
    fi
    if [ "$INSTALLED" = 0 ]; then
      warn "插件安装失败。配置文件已写入，修复后可重试："
      warn "  dsh plugin --profile $PROFILE install"
      warn "  或：cd $PROFILE_DIR && pnpm install"
      warn "常见原因见 docs/TROUBLESHOOTING.md；回滚：bash rollback.sh --profile $PROFILE"
      exit 1
    fi
    ok "插件安装完成"
  fi
else
  warn "已跳过插件安装（--no-install）。稍后请执行："
  warn "  dsh plugin --profile $PROFILE install"
  warn "  或：cd $PROFILE_DIR && pnpm install"
fi

# ------------------------------ 校验 ---------------------------------------
step "校验"
if [ "$DRY_RUN" = 1 ]; then
  warn "dry-run：跳过校验。"
elif [ "$DO_INSTALL" = 0 ]; then
  warn "未安装依赖，跳过校验。"
else
  # 依赖是否真的落地了
  MISSING=""
  if [ -f "$PROFILE_DIR/package.json" ] && [ -n "$NODE_BIN" ]; then
    DEPS="$("$NODE_BIN" -e '
      const fs=require("fs"),p=require("path");
      const dir=process.argv[1];
      const pj=JSON.parse(fs.readFileSync(p.join(dir,"package.json"),"utf8"));
      const deps=Object.keys(pj.dependencies||{});
      const miss=deps.filter(d=>!fs.existsSync(p.join(dir,"node_modules",d,"package.json")));
      process.stdout.write(miss.join(" "));
    ' "$PROFILE_DIR" 2>/dev/null || true)"
    MISSING="$DEPS"
  fi
  if [ -n "$MISSING" ]; then
    warn "以下依赖没有装上：$MISSING"
    warn "可进入 $PROFILE_DIR 手动执行 pnpm install 查看完整报错。"
    exit 1
  fi
  ok "依赖已落地（$(ls -1 "$PROFILE_DIR/node_modules" 2>/dev/null | wc -l | tr -d ' ') 个顶层包）"

  # 配置树是否能组合
  if [ -n "$DSH_BIN" ]; then
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
    warn "没有 dsh 命令，跳过 dump-config 校验（依赖已确认落地）。"
  fi
fi

# ------------------------------ 完成 ---------------------------------------
step "完成"
cat <<EOF
  profile 已就绪：$PROFILE  ($PROFILE_DIR)

  下一步：
    1. 启动：            ${DSH_BIN:-dsh} web                （或 dsh --profile $PROFILE）
       桌面版用户：直接打开应用即可，插件会出现在「设置 → 插件」里
    2. 登录 DeepSeek：   在界面里用设备码登录（deepseek-account）
    3. 设置 GPT 中转 key（可选，llm-pi-ai 的 gpt provider 用）：
         export GPT_API_KEY=sk-xxxx
       然后重启 dsh（该 provider 通过环境变量读取密钥）
    4. 打开设置 → 插件，确认「插件市场 dshmarket」等 12 个插件均已启用

  回滚：  bash rollback.sh --profile $PROFILE
  备份：  $BACKUP_DIR
  排查：  bash doctor.sh
EOF
