#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""UI 截图核对（已停用）。

状态：**停用（2026-11-23）**。本工具依赖的 `[gridmap] rects` 诊断行随 LogRects 一起移除——
`DzGetWindowWidth/Height` 在 UI 初始化时机触发 Game.dll 崩溃（0xc0000409），
见 magic/fixes/2026-11-23-ui-logrects-crash.md。没有可信的帧矩形来源，运行只会误报，
main() 会直接返回 2。
替代方向：用安全常量/配置值，或延后到独立、可禁用的诊断开关，并在作者图实测通过后再启用；
恢复时把本文件的 DISABLED 置回 False，并先补齐新的诊断行来源。

以下为停用前（2026-11-21）的说明，保留供复活参考：
解析/测量逻辑已用合成图单元测试（好图无告警、坏图白块/红/越界三信号全中）；
**端到端未验证**——两次实机回归因游戏失焦暂停超时，日志与截图未能同批产出。
使用前确认截图与日志来自同一次运行、同一窗口分辨率，并用 --offset-x/--offset-y 扣除窗口边框。

推荐用法（坐标来自游戏内日志，不做 CV 猜测）：
    python tools/ui_screenshot_check.py <截图> --diag-file <回归日志> [--offset-x 0 --offset-y 0]

日志行格式（gridMap.j 的 LogRects 输出）：
    [gridmap] rects win=1100x568 root=221,56,658,356 grid=253,112,358,276 info=625,112,222,108 safe=253,81,847,387

检查项（只报数字与可疑信号，最终判断仍由人/agent 对照截图做）：
- 安全区外墨迹/高饱和像素占比（内容越界嫌疑）
- 信息卡区域内平坦高亮块占比（白卡/材质冲突嫌疑）
- 网格区外高饱和红占比（调试框嫌疑）
- 内容边距与左右/上下平衡

⚠ 无 --diag 时退化为旧的亮度投影启发式（实验版，未标定，仅作原始参考）。
"""
import argparse
import json
import re
import sys

try:
    from PIL import Image
except ImportError:
    print("需要 Pillow：pip install pillow", file=sys.stderr)
    sys.exit(2)

# 停用开关：诊断行来源（LogRects）已按 magic/fixes/2026-11-23-ui-logrects-crash.md 移除。
# 恢复前必须先提供新的帧矩形来源，再把 DISABLED 置回 False。
DISABLED = True

RECT_RE = re.compile(r"\[gridmap\]\s+rects\s+(.+)$")


def parse_diag(line):
    m = RECT_RE.search(line)
    if not m:
        return None
    out = {}
    for part in m.group(1).split():
        if "=" not in part:
            continue
        k, v = part.split("=", 1)
        nums = [int(x) for x in v.replace("x", ",").split(",") if x != ""]
        out[k] = nums
    needed = {"win", "root", "grid", "info", "safe"}
    return out if needed.issubset(out) else None


def find_diag_in_file(path):
    last = None
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if "[gridmap] rects" in line:
                last = line
    return last


def flat_block_ratio(img, rect, block=16, mean_min=228, std_max=6):
    x, y, w, h = rect
    crop = img.crop((x, y, x + w, y + h))
    pix = list(crop.getdata())
    cw, chh = crop.size
    total = flat = 0
    for by in range(0, chh - block + 1, block):
        for bx in range(0, cw - block + 1, block):
            total += 1
            vals = [pix[(by + dy) * cw + (bx + dx)] for dy in range(block) for dx in range(block)]
            means = [sum(v[c] for v in vals) / len(vals) for c in range(3)]
            var = sum((sum(v) / 3.0 - sum(means) / 3.0) ** 2 for v in vals) / len(vals)
            if min(means) >= mean_min and var ** 0.5 <= std_max:
                flat += 1
    return (flat / total) if total else 0.0


def ink_mask(p):
    r, g, b = p
    dark = max(r, g, b) <= 100
    sat = max(r, g, b) - min(r, g, b) >= 70
    return dark or sat


def analyze_with_diag(path, diag, ox, oy):
    img = Image.open(path).convert("RGB")
    W, H = img.size
    win_w, win_h = diag["win"][0], diag["win"][1]
    if win_w > W or win_h > H:
        return {"image": str(path), "error": f"日志窗口 {win_w}x{win_h} 大于截图 {W}x{H}，请检查截图/窗口是否一致"}
    rx, ry, rw, rh = diag["root"]; rx += ox; ry += oy
    gx, gy, gw, gh = diag["grid"]; gx += ox; gy += oy
    ix, iy, iw, ih = diag["info"]; ix += ox; iy += oy
    sl, st, sr, sb = diag["safe"]; sl += ox; st += oy; sr += ox; sb += oy

    root_crop = img.crop((rx, ry, rx + rw, ry + rh)).load()

    # 1) 安全区外（根内、安全区外）的墨迹占比
    out_ink = in_area = 0
    for y in range(ry, ry + rh):
        for x in range(rx, rx + rw):
            if sl <= x <= sr and st <= y <= sb:
                continue
            in_area += 1
            if ink_mask(root_crop[x - rx, y - ry]):
                out_ink += 1
    out_ink_ratio = out_ink / in_area if in_area else 0.0

    # 2) 信息卡白块
    white = flat_block_ratio(img, (ix, iy, iw, ih))

    # 3) 网格区外红像素
    red_out = red_area = 0
    for y in range(ry, ry + rh):
        for x in range(rx, rx + rw):
            if gx <= x <= gx + gw and gy <= y <= gy + gh:
                continue
            red_area += 1
            r, g, b = root_crop[x - rx, y - ry]
            if r >= 150 and r - g >= 60 and r - b >= 60:
                red_out += 1
    red_out_ratio = red_out / red_area if red_area else 0.0

    # 4) 内容（墨迹）边距
    minx, miny, maxx, maxy = rw, rh, -1, -1
    for y in range(rh):
        for x in range(rw):
            if ink_mask(root_crop[x, y]):
                minx, miny = min(minx, x), min(miny, y)
                maxx, maxy = max(maxx, x), max(maxy, y)
    margins = None
    lr = tb = None
    if maxx >= 0:
        margins = {"left": minx, "top": miny, "right": rw - 1 - maxx, "bottom": rh - 1 - maxy}
        def ratio(a, b):
            lo, hi = min(a, b), max(a, b)
            return round(hi / lo, 2) if lo > 0 else 999.0
        lr, tb = ratio(margins["left"], margins["right"]), ratio(margins["top"], margins["bottom"])

    res = {
        "image": str(path),
        "image_size": [W, H],
        "diag_win": [win_w, win_h],
        "offset": [ox, oy],
        "rects": {"root": [rx, ry, rw, rh], "grid": [gx, gy, gw, gh], "info": [ix, iy, iw, ih], "safe": [sl, st, sr, sb]},
        "out_of_safe_ink_ratio": round(out_ink_ratio, 4),
        "info_white_block_ratio": round(white, 4),
        "red_outside_grid_ratio": round(red_out_ratio, 4),
        "margins_px": margins,
        "lr_balance_ratio": lr,
        "tb_balance_ratio": tb,
        "flags": [],
    }
    if out_ink_ratio > 0.02:
        res["flags"].append(f"安全区外墨迹占比 {out_ink_ratio:.2%}（内容越界嫌疑）")
    if white > 0.03:
        res["flags"].append(f"信息卡平坦高亮块 {white:.2%}（白卡/材质冲突嫌疑）")
    if red_out_ratio > 0.002:
        res["flags"].append(f"网格区外高饱和红 {red_out_ratio:.2%}（调试框嫌疑）")
    if lr and lr > 3.5:
        res["flags"].append(f"左右留白比 {lr}（失衡嫌疑）")
    return res


def main():
    if DISABLED:
        print("ui_screenshot_check 已停用：依赖的 [gridmap] rects 诊断行已随 LogRects 移除，"
              "无可信帧矩形来源，详见 magic/fixes/2026-11-23-ui-logrects-crash.md。",
              file=sys.stderr)
        return 2
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--diag-file", help="含 [gridmap] rects 行的日志文件（取最后一条）")
    ap.add_argument("--diag-line", help="直接给 rects 日志行")
    ap.add_argument("--offset-x", type=int, default=0, help="游戏窗口在截图内的左上角偏移 x（窗口边框）")
    ap.add_argument("--offset-y", type=int, default=0, help="游戏窗口在截图内的左上角偏移 y（标题栏）")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    line = a.diag_line
    if not line and a.diag_file:
        line = find_diag_in_file(a.diag_file)
    diag = parse_diag(line) if line else None
    if not diag:
        print("未找到/无法解析 [gridmap] rects 诊断行；请用 --diag-file 或 --diag-line 提供。", file=sys.stderr)
        print("（无 diag 的旧启发式模式已停用，避免误判——见 UI设计规范 §10.1）", file=sys.stderr)
        return 2

    r = analyze_with_diag(a.image, diag, a.offset_x, a.offset_y)
    if "error" in r:
        print("错误:", r["error"], file=sys.stderr)
        return 2
    if a.json:
        print(json.dumps(r, ensure_ascii=False, indent=2))
    else:
        print(f"图片: {r['image']} {r['image_size'][0]}x{r['image_size'][1]}  日志窗口: {r['diag_win'][0]}x{r['diag_win'][1]}  偏移: {r['offset']}")
        print(f"rects: root={r['rects']['root']} grid={r['rects']['grid']} info={r['rects']['info']} safe={r['rects']['safe']}")
        print(f"安全区外墨迹: {r['out_of_safe_ink_ratio']:.2%}  信息卡白块: {r['info_white_block_ratio']:.2%}  网格外红: {r['red_outside_grid_ratio']:.3%}")
        if r["margins_px"]:
            m = r["margins_px"]
            print(f"内容边距(px): 左{m['left']} 上{m['top']} 右{m['right']} 下{m['bottom']}  左右比 {r['lr_balance_ratio']}")
        print("可疑信号: " + ("无" if not r["flags"] else ""))
        for f in r["flags"]:
            print("  - " + f)
    return 1 if r["flags"] else 0


if __name__ == "__main__":
    sys.exit(main())
