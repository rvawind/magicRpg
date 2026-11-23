#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""项目入口：调用全局 context-maintenance 技能的体检脚本（单一事实来源）。

项目内不再维护第二份 doc_health.py。脚本本体：
    %USERPROFILE%\\.dsh\\skills\\context-maintenance\\scripts\\doc_health.py

用法：
    python tools/doc_health.py [项目根] [--json]
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(HERE)


def skill_script() -> str:
    home = os.environ.get("USERPROFILE") or os.path.expanduser("~")
    return os.path.join(home, ".dsh", "skills", "context-maintenance", "scripts", "doc_health.py")


def main() -> int:
    target = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else PROJECT_ROOT
    script = skill_script()
    if not os.path.isfile(script):
        print(f"找不到全局体检脚本：{script}", file=sys.stderr)
        print("请确认 ~/.dsh/skills/context-maintenance/ 已安装（见 NOTICE-superpowers.md）。", file=sys.stderr)
        return 2
    args = [sys.executable, script, target] + [a for a in sys.argv[1:] if a.startswith("--")]
    return subprocess.call(args)


if __name__ == "__main__":
    sys.exit(main())
