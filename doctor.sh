#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# DSH 安装体检：只读，不修改任何文件。
# 把输出整段贴回来，就能定位「插件/插件市场没装上」的原因。
#
#   用法: bash doctor.sh [--dsh-home <dir>]
# ---------------------------------------------------------------------------
set -uo pipefail

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"

while [ $# -gt 0 ]; do
  case "$1" in
    --dsh-home) DSH_HOME="${2:?--dsh-home 需要一个值}"; shift 2 ;;
    -h|--help)  sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

line() { printf '\n--- %s ---\n' "$*"; }

line "系统"
printf '时间   : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
printf '发行版 : %s\n' "$( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || uname -s)"
printf '内核   : %s\n' "$(uname -sr)"
printf '架构   : %s\n' "$(uname -m)"

line "运行时"
for c in node pnpm dsh git; do
  if p=$(command -v "$c" 2>/dev/null); then
    v=$("$c" --version 2>/dev/null | head -n1)
    printf '%-5s : %s (%s)\n' "$c" "${v:-版本未知}" "$p"
  else
    printf '%-5s : 未找到\n' "$c"
  fi
done

line "桌面版自带 CLI"
FOUND=""
for base in /opt /usr/lib /usr/share /usr/local /tmp "$HOME/.local/share" "$HOME/Applications"; do
  [ -d "$base" ] || continue
  while IFS= read -r f; do
    [ -n "$f" ] && FOUND="$FOUND$f"$'\n'
  done < <(find "$base" -maxdepth 7 -path '*resources/runtime/cli/bin/dsh' -type f 2>/dev/null | head -n3)
done
if [ -n "$FOUND" ]; then printf '%s' "$FOUND"; else echo "（未找到，如果是桌面版且 PATH 里没有 dsh，插件就无法用命令行安装）"; fi

line "DSH 家目录"
printf 'DSH_HOME = %s\n' "$DSH_HOME"
[ -d "$DSH_HOME" ] && echo "存在" || echo "不存在（DSH 还没运行过？）"
for d in "$DSH_HOME"/profiles/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  printf '\n[profile] %s\n' "$name"
  printf '  package.json     : %s\n' "$([ -f "$d/package.json" ] && echo 有 || echo 缺)"
  printf '  cordis.patch.yml : %s\n' "$([ -f "$d/cordis.patch.yml" ] && echo 有 || echo 缺)"
  printf '  cordis.yml       : %s\n' "$([ -f "$d/cordis.yml" ] && echo 有 || echo 缺)"
  printf '  node_modules     : %s\n' "$([ -d "$d/node_modules" ] && echo "有（$(ls -1 "$d/node_modules" 2>/dev/null | wc -l | tr -d ' ') 个顶层包）" || echo 缺)"
  if [ -f "$d/package.json" ]; then
    echo "  依赖是否落地:"
    node -e '
      const fs=require("fs"),p=require("path"),dir=process.argv[1];
      const pj=JSON.parse(fs.readFileSync(p.join(dir,"package.json"),"utf8"));
      const deps=Object.keys(pj.dependencies||{});
      const bundles=(pj.dsh&&pj.dsh.profile&&pj.dsh.profile.bundles)||[];
      if(!deps.length) console.log("    （package.json 没有 dependencies）");
      for(const d of deps){
        const ok=fs.existsSync(p.join(dir,"node_modules",d,"package.json"));
        console.log("    "+(ok?"✔":"✘")+" "+d);
      }
      console.log("  bundles ("+bundles.length+"): "+bundles.join(", "));
      const nm=fs.existsSync(p.join(dir,"node_modules"));
      console.log("  dshmarket 目录: "+(nm&&fs.existsSync(p.join(dir,"node_modules","dshmarket"))?"有":"没有"));
    ' "$d" 2>&1 | sed 's/^/  /'
  fi
  if command -v dsh >/dev/null 2>&1; then
    err=$(dsh --profile "$name" --dump-config 2>&1 >/dev/null | head -n5)
    if [ -z "$err" ]; then echo "  dump-config: 通过"; else echo "  dump-config: 失败"; printf '%s\n' "$err" | sed 's/^/    /'; fi
  fi
done

line "最近一次安装日志（如果有）"
for f in "$DSH_HOME"/profiles/*/.dump-config.err; do
  [ -f "$f" ] && { echo "== $f"; head -n 20 "$f"; }
done
echo "（完）"
