#!/usr/bin/env bash
# 将 magic-core 工程中「本次修改」的文件同步到 KKWE 的 jass 目录。
#
# 用法:
#   bash tools/sync_to_kkwe.sh              # 同步 git 中相对 HEAD 改动/新增的文件
#   bash tools/sync_to_kkwe.sh --dry-run    # 只列出将复制哪些文件，不写入
#   bash tools/sync_to_kkwe.sh --all        # 同步所有已映射且与目标内容不同的文件（谨慎）
#   bash tools/sync_to_kkwe.sh -- 文件1 文件2   # 指定文件（工程相对路径或绝对路径）
#
# 可用环境变量 KKWE_JASS 覆盖目标目录。

set -uo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JASS="${KKWE_JASS:-C:/Users/admin/Documents/WE/KKWE_nncouVer1.5.7.1/jass}"

# 工程相对路径 -> jass 相对路径；无法映射返回非 0
map_rel() {
    local rel="$1"
    case "$rel" in
        # 目标多一层子目录
        core/nncou/BossChargeSystem.j)
            printf '%s\n' "nncou/BossChargeSystem/BossChargeSystem.j" ;;
        core/nncou/BossChargeSystemInterface.j|core/nncou/BossChargeSystemInterface.cfg)
            printf '%s\n' "nncou/BossChargeSystem/${rel#core/nncou/}" ;;
        # 仅工程侧使用，不同步
        core/nncou/_tmp_update.py)
            return 1 ;;
        # core/** -> jass/**
        core/*)
            printf '%s\n' "${rel#core/}" ;;
        # magic/** -> jass/nncou/magic/**
        magic/*)
            printf '%s\n' "nncou/$rel" ;;
        # 根目录 debug.j -> jass/nncou/debug.j
        debug.j)
            printf '%s\n' "nncou/debug.j" ;;
        *)
            return 1 ;;
    esac
}

DRY=0
ALL=0
EXPLICIT=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run|-n) DRY=1; shift ;;
        --all|-a)     ALL=1; shift ;;
        -h|--help)    sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
        --)           shift; EXPLICIT=("$@"); break ;;
        *)            echo "未知参数: $1" >&2; exit 1 ;;
    esac
done

if [ ! -d "$JASS" ]; then
    echo "错误: 目标目录不存在: $JASS" >&2
    exit 1
fi

# 规范化：绝对路径转工程相对路径
to_rel() {
    local f="$1"
    case "$f" in
        "$PROJ"/*) printf '%s\n' "${f#$PROJ/}" ;;
        /*|[A-Za-z]:/*) printf '%s\n' "$f" ;;
        *)         printf '%s\n' "$f" ;;
    esac
}

FILES=()
if [ ${#EXPLICIT[@]} -gt 0 ]; then
    for f in "${EXPLICIT[@]}"; do
        rel="$(to_rel "$f")"
        case "$rel" in
            /*|[A-Za-z]:/*) echo "跳过(不在工程内): $f" ;;
            *) FILES+=("$rel") ;;
        esac
    done
elif [ "$ALL" = 1 ]; then
    while IFS= read -r -d '' f; do
        rel="${f#$PROJ/}"
        map_rel "$rel" >/dev/null || continue
        FILES+=("$rel")
    done < <(find "$PROJ/core" "$PROJ/magic" -type f -print0; printf '%s\0' "$PROJ/debug.j")
else
    # git diff HEAD 覆盖已暂存与未暂存改动；ls-files 覆盖未跟踪新文件
    while IFS= read -r -d '' f; do FILES+=("$f"); done \
        < <(git -C "$PROJ" diff --name-only -z HEAD 2>/dev/null)
    while IFS= read -r -d '' f; do FILES+=("$f"); done \
        < <(git -C "$PROJ" ls-files --others --exclude-standard -z 2>/dev/null)
fi

if [ ${#FILES[@]} -eq 0 ]; then
    echo "没有需要同步的文件。"
    exit 0
fi

synced=0
skipped=0
failed=0
for rel in "${FILES[@]}"; do
    rel="${rel#./}"
    src="$PROJ/$rel"
    if [ ! -f "$src" ]; then
        echo "跳过(不存在): $rel"
        skipped=$((skipped+1))
        continue
    fi
    if ! dst_rel="$(map_rel "$rel")"; then
        echo "未映射(跳过): $rel"
        skipped=$((skipped+1))
        continue
    fi
    dst="$JASS/$dst_rel"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        echo "一致(跳过): $rel"
        continue
    fi
    if [ "$DRY" = 1 ]; then
        echo "[dry-run] $rel  ->  $dst_rel"
    else
        mkdir -p "$(dirname "$dst")"
        if cp -f "$src" "$dst"; then
            echo "已同步: $rel  ->  $dst_rel"
            synced=$((synced+1))
        else
            echo "失败: $rel" >&2
            failed=$((failed+1))
        fi
    fi
done

echo "---"
if [ "$DRY" = 1 ]; then
    echo "dry-run 结束：待复制 $((${#FILES[@]} - skipped)) 个，跳过 $skipped 个"
else
    echo "同步完成：写入 $synced 个，跳过 $skipped 个，失败 $failed 个"
fi
[ "$failed" -eq 0 ]
