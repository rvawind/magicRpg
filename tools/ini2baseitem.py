#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""baseItem 表格的 CSV -> Lua 转换器。

数据流：

  magic/map/attr/attr.csv     地图级属性注册表，所有系统共用
  magic/map/attr/attr.lua     ↑ 生成物
  baseItem/table/<pack>.csv       一件装备一行，一个属性一列
  baseItem/table/<pack>.text.csv  文本：name / tip / ubertip / description
          │
          ▼  python tools/ini2baseitem.py
  baseItem/data/<pack>.lua    纯数据，不含中文
  baseItem/text/<pack>.lua    文本
  baseItem/report.md          审阅报告

属性注册表不属于任何一个装备包：装备、肉鸽奖励、诅咒等系统都引用同一份。
删除一对 <pack>.csv / <pack>.text.csv 就是删除一个装备包。

初始化时可以从 lni 导出一遍 CSV：

  python tools/ini2baseitem.py export [--force]

只读 item.ini。技能不参与：ability.ini 里的 139 个动态技能是 attr.j
在编译期用 slk 库生成的产物，其余 172 个是普通物编技能。

属性行解析原则（仅导出时使用）：
  - 只提取「标签 + 数值」这种无歧义的行（可带 %）。
  - 带公式（如 神性+3x散华计数）、自定义计数器（「谣言」+1）、
    主动/被动描述，全部不提取，原样留在 ubertip 里。
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import Counter, OrderedDict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]

DEFAULT_INI = ROOT / "core" / "nncou" / "lni" / "item.ini"
DEFAULT_OUT_DIR = ROOT / "magic" / "map" / "equip" / "baseItem"
DEFAULT_TABLE_DIR = DEFAULT_OUT_DIR / "table"
# 属性注册表是地图级的，不属于任何一个装备包。
DEFAULT_ATTR_DIR = ROOT / "magic" / "map" / "attr"

# ---------------------------------------------------------------------------
# 解析用正则
# ---------------------------------------------------------------------------

COLOR_RE = re.compile(r"\|c[0-9a-fA-F]{8}")
RICH_TAG_RE = re.compile(r"\|[a-zA-Z]")
SECTION_RE = re.compile(r"^\[([^\]]+)\]\s*$")
FIELD_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")

# 属性行：标签 + 正负号 + 数值 + 可选 %
ATTR_LINE_RE = re.compile(
    r"^(?P<label>[一-龥A-Za-z_][一-龥A-Za-z0-9_ ]*?)\s*"
    r"(?P<sign>[+\-])\s*(?P<num>\d+(?:\.\d+)?)\s*(?P<pct>%?)\s*(?P<tail>.*)$"
)

# 自定义计数器，例如 「谣言」+1
COUNTER_LINE_RE = re.compile(r"^「[^」]+」\s*[+\-]\s*\d")

# 属性区到此结束
BLOCK_LINE_RE = re.compile(r"^(主动|被动|标签|通过使用|获得后|使用该技能|战斗时|此身)")

# 「被动（唯一）：暴击+20」这类把块标题和属性写在同一行的写法。
BLOCK_PREFIX_RE = re.compile(r"^(主动|被动)(（[^）]*）)?\s*[：:]\s*")

# 原始标签 -> 规范属性 key。只用于 export 初始化 CSV；
# build 时以 magic/map/attr/attr.csv 为准，这里改了不会影响生成结果。
# 同一个 key 可以出现 flat / percent 两种单位，percent 在表里写成字符串，
# 例如 attackSpeed = "20%"。
ATTR_ALIASES: Dict[str, str] = {
    # 基础三围
    "力量": "strength",
    "力量成长": "strengthGrowth",
    "敏捷": "agility",
    "敏捷成长": "agilityGrowth",
    "智力": "intelligence",
    "智力成长": "intelligenceGrowth",
    "全属性": "allStats",
    "全属性成长": "allStatsGrowth",
    "主属性": "mainAttribute",
    "主属性成长": "mainAttributeGrowth",
    # 攻防
    "攻击力": "attack",
    "攻击": "attack",
    "攻击成长": "attackGrowth",
    "护甲": "armor",
    "防御": "armor",
    "防御力": "armor",
    "攻击速度": "attackSpeed",
    "攻击间隔": "attackInterval",
    "移动速度": "moveSpeed",
    "攻击吸血": "lifesteal",
    "近战攻击伤害": "meleeDamage",
    "远程攻击伤害": "rangedDamage",
    "闪避": "dodge",
    # 生命 / 魔法
    "生命值": "maxHp",
    "生命上限": "maxHp",
    "生命回复": "hpRegen",
    "每秒回血": "hpRegen",
    "每秒回固定": "hpRegen",
    # 百分比形态在 JASS 里是另一个 key（CIRCULATING_BLOOD），由解析时按值里的 % 分流
    "每秒回血%": "hpRegenPercent",
    "每秒回损失": "hpRegenLost",
    "魔法值": "maxMp",
    "魔法上限": "maxMp",
    "法力回复": "manaRegen",
    "魔法回复": "manaRegen",
    "每秒回蓝固定": "manaRegen",
    "每秒回蓝百分比": "manaRegenPercent",
    "每秒回蓝损失": "manaRegenLost",
    "魔弹上限": "magicBulletMax",
    "气力上限": "powerMax",
    # 抗性 / 穿透 / 增伤
    "法术抗性": "magicResist",
    "魔抗": "magicResist",
    "物理抗性": "physicalResist",
    "伤害减免": "damageReduction",
    "减伤上限": "damageReductionCap",
    "伤害加成": "damageBonus",
    "物理加成": "physicalBonus",
    "法术加成": "spellBonus",
    "法术伤害": "spellBonus",
    "护甲穿透": "armorPenetration",
    "法术穿透": "spellPenetration",
    "伤害修正": "damageModifier",
    # 暴击：暴击与暴击几率在 attr.j 里是两个 key（STRIKE / STRIKE_CHANCE），不能合并
    "暴击": "crit",
    "暴击几率": "critChance",
    "暴击伤害": "critDamage",
    "暴击抗性": "critResist",
    # 冷却
    "冷却缩减": "cooldownReduction",
    "冷却减免": "cooldownReduction",
    "冷却上限": "cooldownCap",
    # 其他
    "经验效率": "expEfficiency",
    "经验增幅": "expEfficiency",
    "杀敌属性": "killAttribute",
    "普攻属性": "attackAttribute",
    "每秒属性": "secondAttribute",
    "神性": "divinity",
    "幸运": "luck",
}

# 物编字段 -> baseItem 字段。文本字段单独进 text 表。
# oldLevel 是 YDWE 的记录字段，abilList 在本图全部为空，两者丢弃。
FIELD_MAP = {
    "Level": "level",
    "Art": "icon",
    "class": "class",
    "Hotkey": "hotkey",
    "HP": "hp",
    "usable": "usable",
    "file": "file",
    "cooldownID": "cooldown",
}

# 属性引用表（attr.lua）的显示名。缺省取 ATTR_ALIASES 里该 key 的第一个标签。
ATTR_LABEL_OVERRIDES = {
    "maxHp": "生命上限",
    "maxMp": "魔法上限",
    "hpRegen": "每秒回血",
    "crit": "暴击",
    "critChance": "暴击几率",
    "expEfficiency": "经验效率",
}

# 语义上必然是百分比的属性，即使本次数据里只出现固定值也标记 percent。
PERCENT_KEYS = {
    "damageReduction", "damageReductionCap", "damageBonus", "physicalBonus",
    "spellBonus", "critDamage", "critResist", "spellPenetration",
    "physicalResist", "cooldownReduction", "expEfficiency",
    "hpRegenPercent", "hpRegenLost",
    "manaRegenPercent", "manaRegenLost", "dodge",
}

# 同一个标签在 JASS 里按百分比 / 固定值分成两个 key，解析时按值里有没有 % 分流。
PERCENT_KEY_VARIANTS = {
    "hpRegen": "hpRegenPercent",
    "manaRegen": "manaRegenPercent",
}

# 属性值在 JASS 里的存取类型，逐个对照 core/nncou/lua/attr.j：
#   integer -> SaveInteger / LoadInteger
#   real    -> SaveReal / LoadReal
# 这是写入地图数据时的类型，与 percent 无关：百分比也是先按数值存，由消费方解释。
# 只用于 export 初始化 attr.csv；build 时类型以 attr.csv 的 type 列为准。
ATTR_TYPES: Dict[str, str] = {
    # LoadInteger(Item, id, ...)
    "strength": "integer",          # STR_ATTRIBUTE
    "strengthGrowth": "integer",    # STR_GROW
    "agility": "integer",           # AGI_ATTRIBUTE
    "agilityGrowth": "integer",     # AGI_GROW
    "intelligence": "integer",      # INT_ATTRIBUTE
    "intelligenceGrowth": "integer",  # INT_GROW
    "allStats": "integer",          # ITEM_SYSTEM_FULL_ATTRIBUTE
    "allStatsGrowth": "integer",    # ALL_GROW
    "mainAttribute": "integer",     # MAIN_ATTRIBUTE
    "mainAttributeGrowth": "integer",  # PRIMARY_GROW
    "crit": "integer",              # STRIKE
    "magicBulletMax": "integer",    # MAGIC_BULLET_MAX
    "powerMax": "integer",          # POW_MAX
    "killAttribute": "integer",     # ITEM_SYSTEM_STRIKE_PROPERTY
    "attackAttribute": "integer",   # ITEM_SYSTEM_ATTACK_ATTRIBUTES
    "secondAttribute": "integer",   # ITEM_SYSTEM_CYCLIC_PROPERTIES
    # LoadReal(Item, id, ...)
    "attack": "real",               # ITEM_SYSTEM_AGGRESSIVITY
    "armor": "real",                # ITEM_SYSTEM_ARMOR
    "attackSpeed": "real",          # ATK_SPEED
    "attackInterval": "real",       # ATTACK_INTERVAL
    "moveSpeed": "real",            # MOVE_SPEED
    "lifesteal": "real",            # ITEM_SYSTEM_BLOOD_SUCKING
    "maxHp": "real",                # ITEM_SYSTEM_VALUE_OF_LIFE
    "hpRegen": "real",              # CIRCULATING_BLOOD / CIRCULATING_BLOOD2
    "maxMp": "real",                # ITEM_SYSTEM_VALUE_OF_MANA
    "manaRegen": "real",            # CIRCULATING_Mana2
    "magicResist": "real",          # MAGIC_REDUCE
    "physicalResist": "real",       # PHYCICS_REDUCE
    "damageReduction": "real",      # ITEM_SYSTEM_DAMAGE_RESISTANCE
    "damageBonus": "real",          # DAMAGE_ADDEX
    "physicalBonus": "real",        # PHYCICS_ADDEX
    "spellBonus": "real",           # MAGIC_ADDEX
    "armorPenetration": "real",     # PHYCICS_IGNORE
    "critChance": "real",           # ITEM_SYSTEM_STRIKE_CHANCE
    "critDamage": "real",           # ITEM_SYSTEM_VIOLENT_ATTACK
    "critResist": "real",           # STRIKE_REDUCE
    "cooldownReduction": "real",    # COOLDOWN
    "cooldownCap": "real",          # COOLDOWN_UPLIMIT
    "expEfficiency": "real",        # EXP_ADD
    "hpRegenPercent": "real",       # CIRCULATING_BLOOD
    "hpRegenLost": "real",          # CIRCULATING_BLOOD1
    "manaRegenPercent": "real",     # CIRCULATING_Mana
    "manaRegenLost": "real",        # CIRCULATING_Mana1
    "dodge": "real",                # ExtraAttr 闪避
    "meleeDamage": "real",          # MELEE_ATK_EX
    "rangedDamage": "real",         # RANGED_ATK_EX
    "damageModifier": "real",       # DMG_REMIX
    "damageReductionCap": "real",   # DMG_REDUCE_UPLIMIT
}

# attr.j 里没有对应实现、类型按数值语义推断的属性。报告里单独列出。
ATTR_TYPE_INFERRED = {
    "attackGrowth": "integer",      # 与其它成长属性一致
    "spellPenetration": "real",     # 与护甲穿透 (PHYCICS_IGNORE) 同类
    "divinity": "integer",          # 物品里全部是整数
    "luck": "integer",              # 物品里全部是整数
}
ATTR_TYPES.update(ATTR_TYPE_INFERRED)

# label 与 JASS 侧 StringHash("...") 不一致的属性。其余属性 jass = label。
ATTR_JASS_OVERRIDES = {
    "cooldownReduction": "冷却减免",     # StringHash("冷却减免")
    "expEfficiency": "经验增幅",         # EXP_ADD
    "hpRegen": "每秒回固定",             # CIRCULATING_BLOOD2
    "hpRegenPercent": "每秒回百分比",    # CIRCULATING_BLOOD
    "manaRegen": "每秒回蓝固定",         # CIRCULATING_Mana2
    "manaRegenPercent": "每秒回蓝百分比",  # CIRCULATING_Mana
    "manaRegenLost": "每秒回蓝损失",     # CIRCULATING_Mana1
    "hpRegenLost": "每秒回损失",         # CIRCULATING_BLOOD1
}

# JASS 侧还没有实现的属性，只存在于数据里。
ATTR_JASS_MISSING = {"attackGrowth", "spellPenetration", "luck"}

# 属性值由谁写进 YDHT。attr.j 用三个哈希表：
#   Item  = 物品 ID -> 该物品提供的属性值（定义）
#   Skill = 卡片 ID <-> 技能 ID
#   YDHT  = 单位 handle -> 累加后的属性总值（逆天触发器专用哈希表）
# YDHT 是读取方共用的一层：attr.j 读，外部 GUI 触发器也读。
# 区别在于写入路径：
#   attr   = attr.j 看到这个键，会自动从 Item 累加到 YDHT（默认）
#   loader = attr.j 不解析这个键，载入器必须直接写 YDHT；只写 Item 不生效
ATTR_WRITERS = {
    "divinity": "loader",       # 神性，attr.j 不解析，触发器直接读 YDHT
}

# 单位是秒的属性；其余缺省为 flat。
SECONDS_KEYS = {"attackInterval"}

PACK_ORDER = ("cards", "equip", "quest")
PACK_TITLE = {
    "cards": "卡片（_parent=gold 且带 Level）",
    "equip": "装备（_parent=rde1 / ratc）",
    "quest": "任务道具（_parent=gold 且无 Level）",
}


# ---------------------------------------------------------------------------
# 基础工具
# ---------------------------------------------------------------------------

def strip_inline_comment(text: str) -> str:
    """去掉字符串外的行尾 -- 注释。"""
    in_str = False
    esc = False
    i = 0
    while i < len(text):
        ch = text[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        else:
            if ch == '"':
                in_str = True
            elif ch == "-" and i + 1 < len(text) and text[i + 1] == "-":
                return text[:i].rstrip()
        i += 1
    return text.rstrip()


def brace_depth(text: str) -> int:
    depth = 0
    in_str = False
    esc = False
    for ch in text:
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        else:
            if ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
    return depth


def split_top_level(text: str) -> List[str]:
    parts: List[str] = []
    buf: List[str] = []
    depth = 0
    in_str = False
    esc = False
    for ch in text:
        if in_str:
            buf.append(ch)
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        else:
            if ch == '"':
                in_str = True
                buf.append(ch)
            elif ch in "{[(":
                depth += 1
                buf.append(ch)
            elif ch in "}])":
                depth -= 1
                buf.append(ch)
            elif ch == "," and depth == 0:
                parts.append("".join(buf))
                buf = []
            else:
                buf.append(ch)
    if buf:
        parts.append("".join(buf))
    return parts


def unescape_lua_string(text: str) -> str:
    out: List[str] = []
    mapping = {"n": "\n", "r": "\r", "t": "\t", '"': '"', "\\": "\\", "0": "\0"}
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            out.append(mapping.get(nxt, nxt))
            i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def parse_lua_value(text: str) -> Any:
    text = text.strip()
    if not text:
        return None
    if text.startswith("{"):
        end = text.rfind("}")
        inner = text[1:end] if end >= 0 else text[1:]
        return [parse_lua_value(p) for p in split_top_level(inner) if p.strip()]
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        return unescape_lua_string(text[1:-1])
    low = text.lower()
    if low == "nil":
        return None
    if low == "true":
        return True
    if low == "false":
        return False
    if re.fullmatch(r"[+-]?\d+", text):
        return int(text)
    if re.fullmatch(r"[+-]?(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?", text):
        return float(text)
    return text


def strip_rich(text: str) -> str:
    if not isinstance(text, str):
        return ""
    text = COLOR_RE.sub("", text)
    text = text.replace("|n", "\n").replace("|r", "")
    return RICH_TAG_RE.sub("", text)


# ---------------------------------------------------------------------------
# INI 解析
# ---------------------------------------------------------------------------

class Section:
    __slots__ = ("name", "fields")

    def __init__(self, name: str):
        self.name = name
        self.fields: "OrderedDict[str, Any]" = OrderedDict()


def parse_ini(text: str) -> Tuple["OrderedDict[str, Section]", List[str]]:
    sections: "OrderedDict[str, Section]" = OrderedDict()
    duplicates: List[str] = []
    cur: Optional[Section] = None
    lines = text.splitlines()
    i = 0

    while i < len(lines):
        line = lines[i].strip()

        if not line or line.startswith("--"):
            i += 1
            continue

        m = SECTION_RE.match(line)
        if m:
            name = m.group(1).strip()
            if name in sections:
                duplicates.append(name)
            cur = Section(name)
            sections[name] = cur
            i += 1
            continue

        m = FIELD_RE.match(line)
        if not m or cur is None:
            i += 1
            continue

        key = m.group(1)
        value_text = strip_inline_comment(m.group(2).strip())

        depth = brace_depth(value_text)
        while depth > 0 and i + 1 < len(lines):
            i += 1
            next_line = strip_inline_comment(lines[i].strip())
            value_text += "\n" + next_line
            depth += brace_depth(next_line)

        cur.fields[key] = parse_lua_value(value_text)
        i += 1

    return sections, duplicates


# ---------------------------------------------------------------------------
# 属性提取
# ---------------------------------------------------------------------------

def _number(text: str, sign: str) -> Any:
    value = float(text) if "." in text else int(text)
    return -value if sign == "-" else value


def parse_attrs(ubertip: str,
                label_map: Optional[Dict[str, str]] = None
                ) -> Tuple[List[Tuple[str, Any]], List[str], List[str], List[str]]:
    """从 ubertip 里提取属性行。

    返回 (attrs, formulas, counters, unmapped)。label_map 缺省用 ATTR_ALIASES；
    从 CSV 构建时传入 attr.csv 推导出来的标签表。
    逐行扫描：属性行可能出现在一段背景描述之后（例如 I00S），
    所以不按「头部连续行」截断；主动/被动块里的说明行因为带标点，
    不会误匹配 ATTR_LINE_RE。
    """
    label_map = label_map or ATTR_ALIASES
    plain = strip_rich(ubertip or "")
    attrs: List[Tuple[str, Any]] = []
    formulas: List[str] = []
    counters: List[str] = []
    unmapped: List[str] = []

    for raw in plain.split("\n"):
        line = raw.strip()
        if not line:
            continue
        # 「被动（唯一）：暴击+20」——去掉块标题后剩下的才可能是属性行。
        line = BLOCK_PREFIX_RE.sub("", line).strip()
        if not line:
            continue
        if BLOCK_LINE_RE.match(line):
            continue
        if COUNTER_LINE_RE.match(line):
            counters.append(line)
            continue

        m = ATTR_LINE_RE.match(line)
        if not m:
            continue

        label = m.group("label").strip()
        if m.group("tail").strip():
            formulas.append(line)
            continue

        key = label_map.get(label)
        if not key:
            unmapped.append(line)
            continue

        if m.group("pct"):
            key = PERCENT_KEY_VARIANTS.get(key, key)
            value: Any = f"{'-' if m.group('sign') == '-' else ''}{m.group('num')}%"
        else:
            value = _number(m.group("num"), m.group("sign"))
        attrs.append((key, value))

    return attrs, formulas, counters, unmapped


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

def classify(parent: str, has_level: bool) -> str:
    if parent == "gold":
        return "cards" if has_level else "quest"
    return "equip"


def build_item(section: Section) -> Dict[str, Any]:
    f = section.fields

    text = OrderedDict()
    for src, dst in (("Name", "name"), ("Tip", "tip"), ("Ubertip", "ubertip")):
        value = f.get(src)
        if isinstance(value, str) and value:
            text[dst] = value
    description = f.get("Description")
    if isinstance(description, str) and description and description != text.get("ubertip"):
        text["description"] = description

    data: "OrderedDict[str, Any]" = OrderedDict()
    data["parent"] = f.get("_parent") or ""

    for src in ("Level", "Hotkey", "class"):
        if src in f and f[src] not in (None, ""):
            data[FIELD_MAP[src]] = f[src]

    if "Art" in f and isinstance(f["Art"], str):
        data["icon"] = f["Art"]
    if "HP" in f:
        data["hp"] = f["HP"]
    if "usable" in f:
        data["usable"] = bool(f["usable"])
    if "file" in f and isinstance(f["file"], str):
        data["file"] = f["file"]
    if "cooldownID" in f and isinstance(f["cooldownID"], str):
        data["cooldown"] = f["cooldownID"]

    cost = OrderedDict()
    if "goldcost" in f:
        cost["gold"] = f["goldcost"]
    if "lumbercost" in f:
        cost["lumber"] = f["lumbercost"]
    if cost:
        data["cost"] = cost

    stock = OrderedDict()
    if "stockMax" in f:
        stock["max"] = f["stockMax"]
    if "stockRegen" in f:
        stock["regen"] = f["stockRegen"]
    if stock:
        data["stock"] = stock

    if "Buttonpos_1" in f or "Buttonpos_2" in f:
        button = OrderedDict()
        if "Buttonpos_1" in f:
            button["x"] = f["Buttonpos_1"]
        if "Buttonpos_2" in f:
            button["y"] = f["Buttonpos_2"]
        data["button"] = button

    attrs, formulas, counters, unmapped = parse_attrs(f.get("Ubertip") or "")
    if attrs:
        seen = set()
        unique = []
        for key, value in attrs:
            if key in seen:
                continue
            seen.add(key)
            unique.append((key, value))
        attrs = unique
        data["attrs"] = OrderedDict(attrs)

    return {
        "pack": classify(data["parent"], "Level" in f),
        "data": data,
        "text": text,
        "formulas": formulas,
        "counters": counters,
        "unmapped": unmapped,
    }


# ---------------------------------------------------------------------------
# CSV 表
# ---------------------------------------------------------------------------

# <pack>.csv 的固定列；属性列排在后面，顺序由 attr.csv 决定。
META_COLUMNS: List[str] = [
    "parent", "level", "icon", "class", "hotkey", "hp", "usable", "file",
    "cooldown", "cost.gold", "cost.lumber", "stock.max", "stock.regen",
    "button.x", "button.y",
]
STRING_COLUMNS = {"parent", "icon", "class", "hotkey", "file", "cooldown"}
TEXT_COLUMNS: List[str] = ["name", "tip", "ubertip", "description"]
TRUTHY = {"1", "true", "yes", "y", "on", "是"}

INT_RE = re.compile(r"[+-]?\d+")
REAL_RE = re.compile(r"[+-]?(?:\d+\.\d*|\.\d+)")
CODE_RE = re.compile(r"[A-Za-z][A-Za-z0-9_]*")


class TableError(Exception):
    pass


def read_table(path: Path) -> Tuple[List[str], List[Dict[str, str]]]:
    """读 CSV。Excel 的「CSV UTF-8」带 BOM，普通「CSV」是 GBK，两种都接受。"""
    last: Optional[Exception] = None
    for enc in ("utf-8-sig", "gbk"):
        try:
            with path.open("r", encoding=enc, newline="") as fp:
                reader = csv.DictReader(fp)
                rows = list(reader)
                return list(reader.fieldnames or []), rows
        except UnicodeDecodeError as exc:
            last = exc
    raise TableError("%s: 无法按 UTF-8 或 GBK 解码（%s）" % (path, last))


def write_table(path: Path, header: List[str], rows: List[List[Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as fp:
        writer = csv.writer(fp)
        writer.writerow(header)
        writer.writerows(rows)


def is_true(text: str) -> bool:
    return (text or "").strip().lower() in TRUTHY


def split_aliases(text: str) -> List[str]:
    return [part.strip() for part in re.split(r"[;；|]", text or "") if part.strip()]


def set_nested(data: Dict[str, Any], column: str, value: Any) -> None:
    parts = column.split(".")
    cur = data
    for part in parts[:-1]:
        cur = cur.setdefault(part, OrderedDict())
    cur[parts[-1]] = value


def get_nested(data: Dict[str, Any], column: str) -> Any:
    cur: Any = data
    for part in column.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def parse_attr_cell(column: str, text: str, kind: str) -> Any:
    text = text.strip()
    if text.endswith("%"):
        if kind == "integer":
            raise TableError("%s: 整型属性不能带 %%（%s）" % (column, text))
        number = text[:-1]
        if not (INT_RE.fullmatch(number) or REAL_RE.fullmatch(number)):
            raise TableError("%s: 不是数字（%s）" % (column, text))
        return text
    if kind == "integer":
        if not INT_RE.fullmatch(text):
            raise TableError("%s: 整型属性必须是整数（%s）" % (column, text))
        return int(text)
    if INT_RE.fullmatch(text):
        return int(text)
    if REAL_RE.fullmatch(text):
        return float(text)
    raise TableError("%s: 不是数字（%s）" % (column, text))


def parse_cell(column: str, text: str, attr_kinds: Dict[str, str]) -> Any:
    text = (text or "").strip()
    if not text:
        return None
    if column in attr_kinds:
        return parse_attr_cell(column, text, attr_kinds[column])
    if column == "usable":
        if INT_RE.fullmatch(text):
            return int(text) != 0
        return text.lower() in TRUTHY
    if column in STRING_COLUMNS:
        return text
    if INT_RE.fullmatch(text):
        return int(text)
    if REAL_RE.fullmatch(text):
        return float(text)
    raise TableError("%s: 期望数字（%s）" % (column, text))


def load_attr_table(table_dir: Path) -> Tuple["OrderedDict[str, Dict[str, Any]]", Dict[str, str]]:
    """读 attr.csv，返回 (属性表, 标签->key)。标签重复指向不同 key 视为错误。"""
    path = table_dir / "attr.csv"
    if not path.is_file():
        raise TableError("找不到属性表: %s" % path)
    _, rows = read_table(path)
    table: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()
    labels: Dict[str, str] = {}
    for lineno, row in enumerate(rows, start=2):
        key = (row.get("key") or "").strip()
        if not key:
            continue
        if key in table:
            raise TableError("attr.csv:%d: 重复的 key %s" % (lineno, key))
        kind = (row.get("type") or "").strip().lower()
        if kind not in ("integer", "real"):
            raise TableError("attr.csv:%d: %s 的 type 必须是 integer 或 real" % (lineno, key))
        entry: "OrderedDict[str, Any]" = OrderedDict()
        entry["label"] = (row.get("label") or key).strip()
        jass = (row.get("jass") or "").strip()
        if jass:
            entry["jass"] = jass
        writer = (row.get("writer") or "").strip().lower()
        if writer not in ("", "attr", "loader"):
            raise TableError("attr.csv:%d: %s 的 writer 必须是 attr、loader 或留空"
                             % (lineno, key))
        if writer and not jass:
            raise TableError("attr.csv:%d: %s 有 writer=%s 但 jass 为空"
                             % (lineno, key, writer))
        if writer:
            entry["writer"] = writer
        entry["type"] = kind
        aliases = split_aliases(row.get("aliases") or "")
        if aliases:
            entry["aliases"] = aliases
        if is_true(row.get("percent") or ""):
            entry["percent"] = True
        elif (row.get("unit") or "").strip():
            entry["unit"] = row["unit"].strip()
        for name in [entry["label"]] + aliases:
            if name in labels and labels[name] != key:
                raise TableError("attr.csv:%d: 标签 %s 同时属于 %s 和 %s" %
                                 (lineno, name, labels[name], key))
            labels[name] = key
        table[key] = entry
    return table, labels


def discover_packs(table_dir: Path) -> List[str]:
    found = []
    for path in table_dir.glob("*.csv"):
        name = path.name
        if name == "attr.csv" or name.endswith(".text.csv"):
            continue
        found.append(name[:-4])
    return [p for p in PACK_ORDER if p in found] + \
           sorted(p for p in found if p not in PACK_ORDER)


def load_pack(table_dir: Path, pack: str,
              attr_table: "OrderedDict[str, Dict[str, Any]]"
              ) -> Tuple["OrderedDict[str, Dict[str, Any]]",
                         "OrderedDict[str, Dict[str, Any]]",
                         List[str], List[str]]:
    """读一个包的数据表和文本表，返回 (data, text, errors, warnings)。"""
    data_path = table_dir / ("%s.csv" % pack)
    text_path = table_dir / ("%s.text.csv" % pack)
    attr_kinds = {k: v["type"] for k, v in attr_table.items()}
    allowed = set(META_COLUMNS) | set(attr_table)
    errors: List[str] = []
    warnings: List[str] = []

    header, rows = read_table(data_path)
    unknown = [c for c in header if c and c not in allowed and c != "code"]
    if unknown:
        errors.append("%s: 未知列 %s（attr.csv 里没有这些 key）" %
                      (data_path.name, ", ".join(unknown)))

    data: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()
    for lineno, row in enumerate(rows, start=2):
        code = (row.get("code") or "").strip()
        if not code:
            errors.append("%s:%d: 缺少 code" % (data_path.name, lineno))
            continue
        if not CODE_RE.fullmatch(code):
            errors.append("%s:%d: code 只能由字母、数字、下划线组成（%s）" %
                          (data_path.name, lineno, code))
            continue
        if code in data:
            errors.append("%s:%d: 重复的 code %s" % (data_path.name, lineno, code))
            continue
        item: "OrderedDict[str, Any]" = OrderedDict()
        for column in META_COLUMNS:
            if column not in header:
                continue
            try:
                value = parse_cell(column, row.get(column) or "", attr_kinds)
            except TableError as exc:
                errors.append("%s:%d %s: %s" % (data_path.name, lineno, code, exc))
                continue
            if value is not None:
                set_nested(item, column, value)
        attrs: "OrderedDict[str, Any]" = OrderedDict()
        for column in attr_table:
            if column not in header:
                continue
            try:
                value = parse_cell(column, row.get(column) or "", attr_kinds)
            except TableError as exc:
                errors.append("%s:%d %s: %s" % (data_path.name, lineno, code, exc))
                continue
            if value is not None:
                attrs[column] = value
        if attrs:
            item["attrs"] = attrs
        data[code] = item

    text: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()
    if text_path.is_file():
        theader, trows = read_table(text_path)
        unknown = [c for c in theader if c and c not in TEXT_COLUMNS and c != "code"]
        if unknown:
            errors.append("%s: 未知列 %s" % (text_path.name, ", ".join(unknown)))
        for lineno, row in enumerate(trows, start=2):
            code = (row.get("code") or "").strip()
            if not code:
                errors.append("%s:%d: 缺少 code" % (text_path.name, lineno))
                continue
            entry: "OrderedDict[str, Any]" = OrderedDict()
            for column in TEXT_COLUMNS:
                value = row.get(column) or ""
                if value:
                    entry[column] = value
            if entry:
                text[code] = entry
    else:
        errors.append("缺少 %s" % text_path.name)

    for code in data:
        if code not in text:
            warnings.append("%s: 没有文本行（%s.text.csv）" % (code, pack))
    for code in text:
        if code not in data:
            warnings.append("%s: 文本表里有，数据表里没有" % code)
    return data, text, errors, warnings


def export_tables(items: "OrderedDict[str, Dict[str, Any]]",
                  table_dir: Path, attr_dir: Path,
                  attr_rows: "OrderedDict[str, Dict[str, Any]]") -> int:
    """把 INI 解析结果写成 CSV。属性表进 attr_dir，装备包进 table_dir。"""
    attr_header = ["key", "label", "jass", "type", "writer",
                   "percent", "unit", "aliases"]
    attr_lines = []
    for key, entry in attr_rows.items():
        attr_lines.append([
            key,
            entry["label"],
            entry.get("jass", ""),
            entry["type"],
            entry.get("writer", ""),
            "1" if entry.get("percent") else "",
            entry.get("unit", ""),
            ";".join(entry.get("aliases", [])),
        ])
    write_table(attr_dir / "attr.csv", attr_header, attr_lines)

    attr_keys = list(attr_rows)
    data_header = ["code"] + META_COLUMNS + attr_keys
    written = 1
    for pack in PACK_ORDER:
        subset = OrderedDict((c, v) for c, v in items.items() if v["pack"] == pack)
        if not subset:
            continue
        rows = []
        for code, item in sorted(subset.items()):
            data = item["data"]
            row: List[Any] = [code]
            for column in META_COLUMNS:
                value = get_nested(data, column)
                if isinstance(value, bool):
                    value = int(value)
                row.append("" if value is None else value)
            attrs = data.get("attrs", {})
            for key in attr_keys:
                row.append(attrs.get(key, ""))
            rows.append(row)
        write_table(table_dir / ("%s.csv" % pack), data_header, rows)

        text_rows = []
        for code, item in sorted(subset.items()):
            text = item["text"]
            text_rows.append([code] + [text.get(c, "") for c in TEXT_COLUMNS])
        write_table(table_dir / ("%s.text.csv" % pack), ["code"] + TEXT_COLUMNS, text_rows)
        written += 2
    return written


# ---------------------------------------------------------------------------
# Lua 输出
# ---------------------------------------------------------------------------

def lua_key(key: str) -> str:
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        return key
    return '[%s]' % lua_str(key)


def lua_str(text: str) -> str:
    out = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )
    return '"%s"' % out


def lua_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return lua_str(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return ("%g" % value)
    if isinstance(value, dict):
        return "{ %s }" % ", ".join(
            "%s = %s" % (lua_key(k), lua_value(v)) for k, v in value.items()
        )
    if isinstance(value, (list, tuple)):
        return "{ %s }" % ", ".join(lua_value(v) for v in value)
    return lua_str(str(value))


def wrap_fields(fields: List[str], indent: str, width: int = 96) -> List[str]:
    lines: List[str] = []
    buf = ""
    for part in fields:
        candidate = part if not buf else buf + ", " + part
        if buf and len(indent) + len(candidate) > width:
            lines.append(indent + buf + ",")
            buf = part
        else:
            buf = candidate
    if buf:
        lines.append(indent + buf)
    return lines


def emit_data_file(pack: str, entries: "OrderedDict[str, Dict[str, Any]]", source: str) -> str:
    out = [
        "-- Generated by tools/ini2baseitem.py. Do not edit by hand.",
        "-- pack: %s" % pack,
        "-- source: %s" % source,
        "",
        "return {",
    ]
    for code in sorted(entries):
        data = entries[code]
        fields: List[str] = []
        inline = ["%s = %s" % (lua_key(k), lua_value(v)) for k, v in data.items()
                  if k not in ("attrs", "cost", "stock", "button")]
        fields.extend(inline)
        for k in ("cost", "stock", "button"):
            if k in data:
                fields.append("%s = %s" % (k, lua_value(data[k])))
        if "attrs" in data:
            fields.append("attrs = %s" % lua_value(data["attrs"]))
        lines = wrap_fields(fields, "    ")
        out.append("  %s = {" % code)
        out.extend(lines)
        out.append("  },")
    out.append("}")
    return "\n".join(out) + "\n"


def build_attr_table(items: "OrderedDict[str, Dict[str, Any]]") -> "OrderedDict[str, Dict[str, Any]]":
    """生成属性引用表：key -> { label, type, aliases?, percent?, unit? }。

    key 的集合来自 ATTR_ALIASES，所以没在本次数据里出现过的属性也会列出，
    方便之后手工加新装备。
    """
    observed: Dict[str, set] = {}
    for item in items.values():
        for key, value in item["data"].get("attrs", {}).items():
            observed.setdefault(key, set()).add(
                "percent" if isinstance(value, str) else "flat")

    inverse: "OrderedDict[str, List[str]]" = OrderedDict()
    for label, key in ATTR_ALIASES.items():
        inverse.setdefault(key, []).append(label)

    rows: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()
    for key, labels in inverse.items():
        label = ATTR_LABEL_OVERRIDES.get(key, labels[0])
        entry: "OrderedDict[str, Any]" = OrderedDict()
        entry["label"] = label
        if key not in ATTR_JASS_MISSING:
            entry["jass"] = ATTR_JASS_OVERRIDES.get(key, label)
            # 有 JASS 键就一定有写入方：attr.j 转存，或载入器直接写。
            entry["writer"] = ATTR_WRITERS.get(key, "attr")
        entry["type"] = ATTR_TYPES[key]
        aliases = [x for x in labels if x != label]
        if aliases:
            entry["aliases"] = aliases
        if key in PERCENT_KEYS or "percent" in observed.get(key, set()):
            entry["percent"] = True
        elif key in SECONDS_KEYS:
            entry["unit"] = "seconds"
        rows[key] = entry
    return rows


def emit_attr_file(rows: "OrderedDict[str, Dict[str, Any]]", source: str) -> str:
    out = [
        "-- Generated by tools/ini2baseitem.py. Do not edit by hand.",
        "-- 地图级属性注册表：装备、奖励、诅咒等系统共用这一份。",
        "-- label   显示名，也是说明文本里出现的写法",
        "-- jass    JASS 侧 StringHash(\"...\") 的字符串键；没有这一项表示 JASS 尚未实现",
        "-- type    JASS 存取类型：integer = SaveInteger/LoadInteger，real = SaveReal/LoadReal",
        "-- writer  attr = attr.j 从 Item 累加到 YDHT；loader = 载入器直接写 YDHT",
        "-- aliases 说明文本里的其它写法（与 label 不同时才列出）",
        "-- percent 允许百分比写法，数据表里写成 \"20%\"；载入时去掉 % 再按 type 写值",
        "-- unit    数值单位，缺省为 flat",
        "-- source: %s" % source,
        "",
        "return {",
    ]
    for key, entry in rows.items():
        out.append("  %s = %s," % (key, lua_value(entry)))
    out.append("}")
    return "\n".join(out) + "\n"


def emit_text_file(pack: str, entries: "OrderedDict[str, Dict[str, Any]]", source: str) -> str:
    out = [
        "-- Generated by tools/ini2baseitem.py. Do not edit by hand.",
        "-- pack: %s" % pack,
        "-- source: %s" % source,
        "",
        "return {",
    ]
    for code in sorted(entries):
        text = entries[code]
        out.append("  %s = {" % code)
        for key, value in text.items():
            out.append("    %s = %s," % (key, lua_str(value)))
        out.append("  },")
    out.append("}")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# 报告
# ---------------------------------------------------------------------------

def attr_unit(value: Any) -> str:
    if isinstance(value, str):
        return "percent"
    return "flat"


def build_report(items: "OrderedDict[str, Dict[str, Any]]",
                 attr_rows: "OrderedDict[str, Dict[str, Any]]",
                 label_map: Dict[str, str],
                 source_name: str, attr_source: str, warnings: List[str]) -> str:
    lines: List[str] = []
    lines.append("# baseItem 转换报告")
    lines.append("")
    lines.append("- 生成器：`tools/ini2baseitem.py`")
    lines.append("- 装备表：`%s`" % source_name)
    lines.append("- 属性注册表：`%s/attr.csv`（地图级）" % attr_source)
    lines.append("")

    packs = Counter(v["pack"] for v in items.values())
    lines.append("## 统计")
    lines.append("")
    lines.append("| 项目 | 数量 |")
    lines.append("|---|---|")
    lines.append("| 物品 | %d |" % len(items))
    for pack in PACK_ORDER:
        if packs.get(pack):
            lines.append("| %s | %d |" % (PACK_TITLE[pack], packs[pack]))
    for pack in sorted(packs):
        if pack not in PACK_ORDER:
            lines.append("| `%s` | %d |" % (pack, packs[pack]))
    with_attrs = sum(1 for v in items.values() if "attrs" in v["data"])
    attr_count = sum(len(v["data"].get("attrs", {})) for v in items.values())
    lines.append("| 有属性的物品 | %d |" % with_attrs)
    lines.append("| 属性条目 | %d |" % attr_count)
    lines.append("")

    lines.append("## 字段映射")
    lines.append("")
    lines.append("| 物编字段 | baseItem | 说明 |")
    lines.append("|---|---|---|")
    mapping = [
        ("_parent", "parent", "继承父物品"),
        ("Level", "level", "等级"),
        ("Art", "icon", "图标"),
        ("class", "class", "类别"),
        ("Hotkey", "hotkey", "热键"),
        ("HP", "hp", "生命值"),
        ("usable", "usable", "可主动使用"),
        ("file", "file", "模型/音效文件"),
        ("cooldownID", "cooldown", "冷却技能"),
        ("goldcost", "cost.gold", "金币价格"),
        ("lumbercost", "cost.lumber", "木材价格"),
        ("stockMax", "stock.max", "库存上限"),
        ("stockRegen", "stock.regen", "库存恢复"),
        ("Buttonpos_1/2", "button.x / button.y", "按钮位置"),
        ("Name/Tip/Ubertip/Description", "text 表", "文本"),
        ("oldLevel", "（丢弃）", "YDWE 记录字段"),
        ("abilList", "（丢弃）", "本图全部为空"),
    ]
    for src, dst, note in mapping:
        lines.append("| `%s` | `%s` | %s |" % (src, dst, note))
    lines.append("")

    lines.append("## 属性注册表（%s/attr.lua）" % attr_source)
    lines.append("")
    lines.append("这是地图级注册表，不属于任何一个装备包；装备表只消费其中一部分。")
    lines.append("`aliases` 是说明文本里的其它写法。")
    lines.append("")
    lines.append("`type` 是写入地图数据时用的 JASS 存取类型，取自 `attr.j` 里对应的 "
                 "`SaveInteger` / `SaveReal`。")
    lines.append("`单位` 只影响数值怎么读（是否带 `%`、是否是秒），与 `type` 相互独立。")
    lines.append("")
    lines.append("| key | 显示名 | JASS 键 | type | 写入方 | 单位 | aliases |")
    lines.append("|---|---|---|---|---|---|---|")
    for key, entry in attr_rows.items():
        kind = "percent" if entry.get("percent") else entry.get("unit", "flat")
        alias = "、".join(entry.get("aliases", []))
        jtype = entry["type"] + ("（推断）" if key in ATTR_TYPE_INFERRED else "")
        jass = entry.get("jass", "（未实现）")
        writer = {"attr": "attr.j", "loader": "载入器"}.get(
            entry.get("writer"), "—")
        lines.append("| `%s` | %s | %s | %s | %s | %s | %s |" %
                     (key, entry["label"], jass, jtype, writer, kind, alias))
    lines.append("")
    lines.append("`attr.j` 用到的三个哈希表：`Item`（物品 ID → 属性值）、"
                 "`Skill`（卡片 ↔ 技能）、`YDHT`（单位 handle → 属性总值）。"
                 "`YDHT` 是逆天触发器专用的，外部 GUI 触发器可以直接读；"
                 "attr.j 和触发器都可以是读取方，区别只在写入方。")
    lines.append("")

    if ATTR_TYPE_INFERRED:
        lines.append("推断项说明：这些属性在 `attr.j` 里没有单独实现，"
                     "类型按同类属性或物品里的实际取值确定。")
        lines.append("")
        for key in ATTR_TYPE_INFERRED:
            if key in attr_rows:
                lines.append("- `%s`（%s）：%s" %
                             (key, attr_rows[key]["label"], ATTR_TYPES[key]))
        lines.append("")

    usage = Counter(key for item in items.values()
                    for key in item["data"].get("attrs", {}))
    by_loader = sorted((key for key in usage
                        if attr_rows.get(key, {}).get("writer") == "loader"),
                       key=lambda key: -usage[key])
    if by_loader:
        lines.append("## 需要载入器直接写 YDHT 的属性")
        lines.append("")
        lines.append("`attr.j` 不解析这些键，但外部触发器从 `YDHT` 直接读取。"
                     "载入器必须把值写进 `YDHT`（单位 handle 作主键），"
                     "只写 `Item` 表不会生效。")
        lines.append("")
        lines.append("| key | 显示名 | JASS 键 | 使用次数 |")
        lines.append("|---|---|---|---|")
        for key in by_loader:
            lines.append("| `%s` | %s | %s | %d |" %
                         (key, attr_rows[key]["label"], attr_rows[key]["jass"],
                          usage[key]))
        lines.append("")

    unbound = sorted((key for key in usage if not attr_rows.get(key, {}).get("jass")),
                     key=lambda key: -usage[key])
    if unbound:
        lines.append("## 还没有 JASS 实现的属性")
        lines.append("")
        lines.append("这些属性已经用在装备上，但 `attr.j` / `NNCouExtraAttr.j` / "
                     "外部触发器里都没有读写逻辑；载入时数据可以写入，"
                     "游戏逻辑不会生效。")
        lines.append("")
        lines.append("| key | 显示名 | 使用次数 |")
        lines.append("|---|---|---|")
        for key in unbound:
            lines.append("| `%s` | %s | %d |" %
                         (key, attr_rows[key]["label"], usage[key]))
        lines.append("")

    conflicts = [(code, key, value) for code, item in items.items()
                 for key, value in item["data"].get("attrs", {}).items()
                 if isinstance(value, str) and attr_rows.get(key, {}).get("type") == "integer"]
    if conflicts:
        lines.append("## 类型冲突")
        lines.append("")
        lines.append("整型属性出现了百分比写法，载入时会被截断。")
        lines.append("")
        lines.append("| 物品 | key | 值 |")
        lines.append("|---|---|---|")
        for code, key, value in conflicts:
            lines.append("| %s | `%s` | `%s` |" % (code, key, value))
        lines.append("")

    catalog: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()
    for code in sorted(items):
        for key, value in items[code]["data"].get("attrs", {}).items():
            unit = attr_unit(value)
            if unit == "flat" and attr_rows.get(key, {}).get("unit") == "seconds":
                unit = "seconds"
            bucket = catalog.setdefault(key, {"units": Counter(), "examples": []})
            bucket["units"][unit] += 1
            numeric = float(str(value).rstrip("%"))
            bucket.setdefault("min", numeric)
            bucket["min"] = min(bucket["min"], numeric)
            bucket.setdefault("max", numeric)
            bucket["max"] = max(bucket["max"], numeric)
            if len(bucket["examples"]) < 4:
                bucket["examples"].append(code)

    lines.append("## 属性目录")
    lines.append("")
    lines.append("| key | 单位 | 次数 | 范围 | 示例 |")
    lines.append("|---|---|---|---|---|")
    for key, bucket in sorted(catalog.items(), key=lambda kv: -sum(kv[1]["units"].values())):
        units = "/".join(sorted(bucket["units"]))
        total = sum(bucket["units"].values())
        lo, hi = bucket["min"], bucket["max"]
        rng = "%g ~ %g" % (lo, hi) if lo != hi else "%g" % lo
        lines.append("| `%s` | %s | %d | %s | %s |" %
                     (key, units, total, rng, ", ".join(bucket["examples"])))
    lines.append("")

    # 文本始终是 ubertip 的原样拷贝，所以可以反过来检查数据表有没有漏写。
    analysis: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()
    for code in items:
        parsed, formulas, counters, unmapped = parse_attrs(
            items[code]["text"].get("ubertip", ""), label_map)
        analysis[code] = {
            "formulas": formulas, "counters": counters,
            "unmapped": unmapped, "parsed": parsed,
        }

    def dump(title: str, field: str, note: str) -> None:
        rows = [(code, line) for code, a in analysis.items() for line in a[field]]
        if not rows:
            return
        lines.append("## %s" % title)
        lines.append("")
        lines.append(note)
        lines.append("")
        lines.append("| 物品 | 行 |")
        lines.append("|---|---|")
        for code, line in sorted(rows):
            lines.append("| %s | %s |" % (code, line.replace("|", "\\|")))
        lines.append("")

    dump("未进入 attrs 的公式行", "formulas",
         "带 `x`、额外 `+` 或中文变量的行。按要求不建模，保留在 `ubertip` 里。")
    dump("自定义计数器行", "counters",
         "例如 `「谣言」+1`，不是通用属性。保留在 `ubertip` 里。")
    dump("未映射的属性标签", "unmapped",
         "格式是属性行，但标签不在 `attr.csv` 的 label/aliases 里。")

    mismatches: List[Tuple[str, str, str]] = []
    for code in sorted(items):
        expected: "OrderedDict[str, Any]" = OrderedDict()
        for key, value in analysis[code]["parsed"]:
            expected.setdefault(key, value)
        actual = items[code]["data"].get("attrs", {})
        for key, value in expected.items():
            if key not in actual:
                mismatches.append((code, key, "文本 %s / 数据表缺失" % value))
            elif str(actual[key]) != str(value):
                mismatches.append((code, key, "文本 %s / 数据 %s" % (value, actual[key])))
        for key, value in actual.items():
            if key not in expected:
                mismatches.append((code, key, "文本解析不到 / 数据 %s" % value))
    if mismatches:
        lines.append("## 文本与数据不一致")
        lines.append("")
        lines.append("这些行需要你确认：要么补数据列，要么改 ubertip。")
        lines.append("")
        lines.append("| 物品 | key | 说明 |")
        lines.append("|---|---|---|")
        for code, key, note in mismatches:
            lines.append("| %s | `%s` | %s |" % (code, key, note))
        lines.append("")

    no_attrs = [code for code in sorted(items) if "attrs" not in items[code]["data"]]
    if no_attrs:
        lines.append("## 没有属性的物品")
        lines.append("")
        lines.append("| 物品 | 名称 | pack |")
        lines.append("|---|---|---|")
        for code in no_attrs:
            name = items[code]["text"].get("name", "")
            lines.append("| %s | %s | %s |" % (code, name, items[code]["pack"]))
        lines.append("")

    if warnings:
        lines.append("## 警告")
        lines.append("")
        for text in warnings:
            lines.append("- %s" % text)
        lines.append("")

    lines.append("## 约定")
    lines.append("")
    lines.append("1. 物品数据表不放中文；中文只出现在 `attr.lua`（属性显示名）和 text 表。")
    lines.append("2. `attrs` 的 key 是规范英文名，值默认是数字；带 `%` 的写成字符串，")
    lines.append("   例如 `attackSpeed = \"20%\"`，因为同一个 key 可能同时出现固定值和百分比。")
    lines.append("3. 源表是 `table/*.csv`；`<pack>.csv` 一行一件装备，")
    lines.append("   属性列的顺序和是否合法由 `attr.csv` 决定。")
    lines.append("4. 空单元格表示没有这一项；`description` 留空表示与 `ubertip` 相同。")
    lines.append("5. `attr.lua` 的 `type` 决定写值方式：`integer` 用 `SaveInteger`，"
                 "`real` 用 `SaveReal`；")
    lines.append("   `percent` 只表示值后面可能带 `%`，去掉 `%` 后仍按 `type` 写。")
    lines.append("   整型属性写小数会被 JASS 截断，转换器会把这种情况列进「类型冲突」。")
    lines.append("")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path)


def cmd_export(args) -> int:
    ini_path = Path(args.ini)
    if not ini_path.is_file():
        print("找不到输入文件: %s" % ini_path, file=sys.stderr)
        return 2

    raw_text = ini_path.read_text(encoding="utf-8")
    sections, _duplicates = parse_ini(raw_text)
    items: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()
    for code, section in sections.items():
        items[code] = build_item(section)

    table_dir = Path(args.table_dir)
    attr_dir = Path(args.attr_dir)
    existing = list(table_dir.glob("*.csv")) if table_dir.is_dir() else []
    if (attr_dir / "attr.csv").is_file():
        existing.append(attr_dir / "attr.csv")
    if existing and not args.force:
        print("目标位置已有 %d 个 CSV，未覆盖：%s, %s" %
              (len(existing), table_dir, attr_dir), file=sys.stderr)
        print("确认要重新导出请加 --force（会丢失手工修改）", file=sys.stderr)
        return 2

    attr_rows = build_attr_table(items)
    written = export_tables(items, table_dir, attr_dir, attr_rows)
    counts = Counter(item["pack"] for item in items.values())
    print("已导出 CSV: %s + %s/attr.csv（%d 个文件）" % (table_dir, attr_dir, written))
    print("统计: items=%d cards=%d equip=%d quest=%d attrKeys=%d attrs=%d" % (
        len(items), counts["cards"], counts["equip"], counts["quest"], len(attr_rows),
        sum(len(item["data"].get("attrs", {})) for item in items.values()),
    ))
    return 0


def cmd_build(args) -> int:
    table_dir = Path(args.table_dir)
    attr_dir = Path(args.attr_dir)
    if not table_dir.is_dir():
        print("找不到表格目录: %s" % table_dir, file=sys.stderr)
        return 2

    try:
        attr_rows, label_map = load_attr_table(attr_dir)
    except TableError as exc:
        print("错误: %s" % exc, file=sys.stderr)
        return 1

    packs = discover_packs(table_dir)
    if not packs:
        print("表格目录里没有 <pack>.csv: %s" % table_dir, file=sys.stderr)
        return 1

    for path in sorted(table_dir.glob("*.text.csv")):
        pack = path.name[:-len(".text.csv")]
        if pack not in packs:
            print("警告: %s 没有对应的 %s.csv，已忽略" % (path.name, pack), file=sys.stderr)

    items: "OrderedDict[str, Dict[str, Any]]" = OrderedDict()
    errors: List[str] = []
    warnings: List[str] = []
    for pack in packs:
        data, text, errs, warns = load_pack(table_dir, pack, attr_rows)
        errors.extend(errs)
        warnings.extend(warns)
        for code, item in data.items():
            if code in items:
                errors.append("code %s 同时出现在多个包里" % code)
                continue
            items[code] = {"pack": pack, "data": item, "text": text.get(code, {})}

    if errors:
        for text in errors:
            print("错误: %s" % text, file=sys.stderr)
        print("共 %d 个错误，未生成任何文件。" % len(errors), file=sys.stderr)
        return 1

    out_dir = Path(args.out_dir)
    data_dir = out_dir / "data"
    text_dir = out_dir / "text"
    data_dir.mkdir(parents=True, exist_ok=True)
    text_dir.mkdir(parents=True, exist_ok=True)
    attr_dir.mkdir(parents=True, exist_ok=True)
    source = rel(table_dir)
    attr_source = rel(attr_dir)

    (attr_dir / "attr.lua").write_text(
        emit_attr_file(attr_rows, "%s/attr.csv" % attr_source), encoding="utf-8")

    for pack in packs:
        subset = OrderedDict((c, v["data"]) for c, v in items.items() if v["pack"] == pack)
        texts = OrderedDict((c, v["text"]) for c, v in items.items() if v["pack"] == pack)
        (data_dir / ("%s.lua" % pack)).write_text(
            emit_data_file(pack, subset, "%s/%s.csv" % (source, pack)), encoding="utf-8")
        (text_dir / ("%s.lua" % pack)).write_text(
            emit_text_file(pack, texts, "%s/%s.text.csv" % (source, pack)),
            encoding="utf-8")

    # 包被删除后，遗留下来的 Lua 也要删掉，否则载入器仍会加载它。
    for directory in (data_dir, text_dir):
        for path in sorted(directory.glob("*.lua")):
            if path.stem not in packs:
                path.unlink()
                print("已删除过期文件: %s" % rel(path))

    report_path = Path(args.report) if args.report else out_dir / "report.md"
    report_path.write_text(
        build_report(items, attr_rows, label_map, source, attr_source, warnings),
        encoding="utf-8")

    counts = Counter(item["pack"] for item in items.values())
    print("已生成: %s" % out_dir)
    print("        %s" % data_dir)
    print("        %s" % text_dir)
    print("属性表: %s" % (attr_dir / "attr.lua"))
    print("报告:   %s" % report_path)
    print("统计: items=%d packs=%d attrKeys=%d attrs=%d" % (
        len(items), len(packs), len(attr_rows),
        sum(len(item["data"].get("attrs", {})) for item in items.values()),
    ))
    for pack in packs:
        print("  %-8s %d" % (pack, counts[pack]))
    for text in warnings:
        print("警告: %s" % text, file=sys.stderr)
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="baseItem：CSV 表格 -> Lua")
    parser.add_argument("command", nargs="?", default="build", choices=["build", "export"],
                        help="build=读 CSV 生成 Lua（默认），export=从 item.ini 初始化 CSV")
    parser.add_argument("--ini", default=str(DEFAULT_INI), help="export 的输入 item.ini")
    parser.add_argument("--table-dir", default=str(DEFAULT_TABLE_DIR), help="装备 CSV 目录")
    parser.add_argument("--attr-dir", default=str(DEFAULT_ATTR_DIR), help="属性注册表目录")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Lua 输出目录")
    parser.add_argument("--report", default=None, help="报告路径，默认 <out-dir>/report.md")
    parser.add_argument("--force", action="store_true", help="export 时覆盖已有 CSV")
    args = parser.parse_args(argv)

    if args.command == "export":
        return cmd_export(args)
    return cmd_build(args)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    raise SystemExit(main())
