# baseItem 转换报告

- 生成器：`tools/ini2baseitem.py`
- 装备表：`magic/map/equip/baseItem/table`
- 属性注册表：`magic/map/attr/attr.csv`（地图级）

## 统计

| 项目 | 数量 |
|---|---|
| 物品 | 121 |
| 卡片（_parent=gold 且带 Level） | 78 |
| 装备（_parent=rde1 / ratc） | 39 |
| 任务道具（_parent=gold 且无 Level） | 4 |
| 有属性的物品 | 103 |
| 属性条目 | 243 |

## 字段映射

| 物编字段 | baseItem | 说明 |
|---|---|---|
| `_parent` | `parent` | 继承父物品 |
| `Level` | `level` | 等级 |
| `Art` | `icon` | 图标 |
| `class` | `class` | 类别 |
| `Hotkey` | `hotkey` | 热键 |
| `HP` | `hp` | 生命值 |
| `usable` | `usable` | 可主动使用 |
| `file` | `file` | 模型/音效文件 |
| `cooldownID` | `cooldown` | 冷却技能 |
| `goldcost` | `cost.gold` | 金币价格 |
| `lumbercost` | `cost.lumber` | 木材价格 |
| `stockMax` | `stock.max` | 库存上限 |
| `stockRegen` | `stock.regen` | 库存恢复 |
| `Buttonpos_1/2` | `button.x / button.y` | 按钮位置 |
| `Name/Tip/Ubertip/Description` | `text 表` | 文本 |
| `oldLevel` | `（丢弃）` | YDWE 记录字段 |
| `abilList` | `（丢弃）` | 本图全部为空 |

## 属性注册表（magic/map/attr/attr.lua）

这是地图级注册表，不属于任何一个装备包；装备表只消费其中一部分。
`aliases` 是说明文本里的其它写法。

`type` 是写入地图数据时用的 JASS 存取类型，取自 `attr.j` 里对应的 `SaveInteger` / `SaveReal`。
`单位` 只影响数值怎么读（是否带 `%`、是否是秒），与 `type` 相互独立。

| key | 显示名 | JASS 键 | type | 写入方 | 单位 | aliases |
|---|---|---|---|---|---|---|
| `strength` | 力量 | 力量 | integer | attr.j | flat |  |
| `strengthGrowth` | 力量成长 | 力量成长 | integer | attr.j | flat |  |
| `agility` | 敏捷 | 敏捷 | integer | attr.j | flat |  |
| `agilityGrowth` | 敏捷成长 | 敏捷成长 | integer | attr.j | flat |  |
| `intelligence` | 智力 | 智力 | integer | attr.j | flat |  |
| `intelligenceGrowth` | 智力成长 | 智力成长 | integer | attr.j | flat |  |
| `allStats` | 全属性 | 全属性 | integer | attr.j | flat |  |
| `allStatsGrowth` | 全属性成长 | 全属性成长 | integer | attr.j | flat |  |
| `mainAttribute` | 主属性 | 主属性 | integer | attr.j | flat |  |
| `mainAttributeGrowth` | 主属性成长 | 主属性成长 | integer | attr.j | flat |  |
| `attack` | 攻击力 | 攻击力 | real | attr.j | flat | 攻击 |
| `attackGrowth` | 攻击成长 | （未实现） | integer（推断） | — | flat |  |
| `armor` | 护甲 | 护甲 | real | attr.j | flat | 防御、防御力 |
| `attackSpeed` | 攻击速度 | 攻击速度 | real | attr.j | percent |  |
| `attackInterval` | 攻击间隔 | 攻击间隔 | real | attr.j | seconds |  |
| `moveSpeed` | 移动速度 | 移动速度 | real | attr.j | flat |  |
| `lifesteal` | 攻击吸血 | 攻击吸血 | real | attr.j | percent |  |
| `meleeDamage` | 近战攻击伤害 | 近战攻击伤害 | real | attr.j | flat |  |
| `rangedDamage` | 远程攻击伤害 | 远程攻击伤害 | real | attr.j | flat |  |
| `dodge` | 闪避 | 闪避 | real | attr.j | percent |  |
| `maxHp` | 生命上限 | 生命上限 | real | attr.j | flat | 生命值 |
| `hpRegen` | 每秒回血 | 每秒回固定 | real | attr.j | flat | 生命回复、每秒回固定 |
| `hpRegenPercent` | 每秒回血% | 每秒回百分比 | real | attr.j | percent |  |
| `hpRegenLost` | 每秒回损失 | 每秒回损失 | real | attr.j | percent |  |
| `maxMp` | 魔法上限 | 魔法上限 | real | attr.j | flat | 魔法值 |
| `manaRegen` | 法力回复 | 每秒回蓝固定 | real | attr.j | flat | 魔法回复、每秒回蓝固定 |
| `manaRegenPercent` | 每秒回蓝百分比 | 每秒回蓝百分比 | real | attr.j | percent |  |
| `manaRegenLost` | 每秒回蓝损失 | 每秒回蓝损失 | real | attr.j | percent |  |
| `magicBulletMax` | 魔弹上限 | 魔弹上限 | integer | attr.j | flat |  |
| `powerMax` | 气力上限 | 气力上限 | integer | attr.j | flat |  |
| `magicResist` | 法术抗性 | 法术抗性 | real | attr.j | percent | 魔抗 |
| `physicalResist` | 物理抗性 | 物理抗性 | real | attr.j | percent |  |
| `damageReduction` | 伤害减免 | 伤害减免 | real | attr.j | percent |  |
| `damageReductionCap` | 减伤上限 | 减伤上限 | real | attr.j | percent |  |
| `damageBonus` | 伤害加成 | 伤害加成 | real | attr.j | percent |  |
| `physicalBonus` | 物理加成 | 物理加成 | real | attr.j | percent |  |
| `spellBonus` | 法术加成 | 法术加成 | real | attr.j | percent | 法术伤害 |
| `armorPenetration` | 护甲穿透 | 护甲穿透 | real | attr.j | percent |  |
| `spellPenetration` | 法术穿透 | （未实现） | real（推断） | — | percent |  |
| `damageModifier` | 伤害修正 | 伤害修正 | real | attr.j | flat |  |
| `crit` | 暴击 | 暴击 | integer | attr.j | flat |  |
| `critChance` | 暴击几率 | 暴击几率 | real | attr.j | percent |  |
| `critDamage` | 暴击伤害 | 暴击伤害 | real | attr.j | percent |  |
| `critResist` | 暴击抗性 | 暴击抗性 | real | attr.j | percent |  |
| `cooldownReduction` | 冷却缩减 | 冷却减免 | real | attr.j | percent | 冷却减免 |
| `cooldownCap` | 冷却上限 | 冷却上限 | real | attr.j | percent |  |
| `expEfficiency` | 经验效率 | 经验增幅 | real | attr.j | percent | 经验增幅 |
| `killAttribute` | 杀敌属性 | 杀敌属性 | integer | attr.j | flat |  |
| `attackAttribute` | 普攻属性 | 普攻属性 | integer | attr.j | flat |  |
| `secondAttribute` | 每秒属性 | 每秒属性 | integer | attr.j | flat |  |
| `divinity` | 神性 | 神性 | integer（推断） | 载入器 | flat |  |
| `luck` | 幸运 | （未实现） | integer（推断） | — | flat |  |

`attr.j` 用到的三个哈希表：`Item`（物品 ID → 属性值）、`Skill`（卡片 ↔ 技能）、`YDHT`（单位 handle → 属性总值）。`YDHT` 是逆天触发器专用的，外部 GUI 触发器可以直接读；attr.j 和触发器都可以是读取方，区别只在写入方。

推断项说明：这些属性在 `attr.j` 里没有单独实现，类型按同类属性或物品里的实际取值确定。

- `attackGrowth`（攻击成长）：integer
- `spellPenetration`（法术穿透）：real
- `divinity`（神性）：integer
- `luck`（幸运）：integer

## 需要载入器直接写 YDHT 的属性

`attr.j` 不解析这些键，但外部触发器从 `YDHT` 直接读取。载入器必须把值写进 `YDHT`（单位 handle 作主键），只写 `Item` 表不会生效。

| key | 显示名 | JASS 键 | 使用次数 |
|---|---|---|---|
| `divinity` | 神性 | 神性 | 11 |

## 还没有 JASS 实现的属性

这些属性已经用在装备上，但 `attr.j` / `NNCouExtraAttr.j` / 外部触发器里都没有读写逻辑；载入时数据可以写入，游戏逻辑不会生效。

| key | 显示名 | 使用次数 |
|---|---|---|
| `attackGrowth` | 攻击成长 | 1 |
| `luck` | 幸运 | 1 |
| `spellPenetration` | 法术穿透 | 1 |

## 属性目录

| key | 单位 | 次数 | 范围 | 示例 |
|---|---|---|---|---|
| `intelligence` | flat | 22 | 8 ~ 120 | I004, I007, I008, I00C |
| `attack` | flat | 20 | 5 ~ 220 | I005, I006, I00A, I00X |
| `maxHp` | flat | 19 | 500 ~ 2500 | I004, I00A, I01E, I02Q |
| `agility` | flat | 17 | 6 ~ 120 | I004, I006, I00K, I01F |
| `strength` | flat | 14 | 5 ~ 100 | I005, I01F, I02O, I02T |
| `attackSpeed` | flat/percent | 12 | -100 ~ 80 | I006, I00K, I00M, I00O |
| `allStats` | flat | 12 | -10 ~ 50 | I009, I00G, I00P, I00Z |
| `magicResist` | flat/percent | 12 | 8 ~ 40 | I00L, I01A, I01E, I02Q |
| `divinity` | flat | 11 | 1 ~ 5 | I00O, I012, I013, I014 |
| `damageReduction` | percent | 10 | -25 ~ 25 | I00G, I00N, I00O, I00S |
| `expEfficiency` | percent | 10 | -10 | I012, I013, I014, I015 |
| `cooldownReduction` | flat/percent | 9 | -100 ~ 20 | I00D, I00H, I00S, I013 |
| `armor` | flat | 8 | -20 ~ 90 | I00L, I00T, I017, I01M |
| `intelligenceGrowth` | flat | 7 | 2 ~ 4 | I00B, I00C, I00R, I00V |
| `maxMp` | flat | 6 | 200 ~ 500 | I007, I008, I00V, I010 |
| `crit` | flat | 6 | 4 ~ 30 | I00F, I01Q, I01V, I01Z |
| `moveSpeed` | flat | 5 | 20 ~ 80 | I004, I00J, I02Q, I032 |
| `magicBulletMax` | flat | 4 | 10 | I00B, I00V, I011, I02A |
| `powerMax` | flat | 4 | 10 | I00F, I00W, I01N, I01S |
| `damageBonus` | percent | 4 | -25 ~ 25 | I015, I019, I021, I02C |
| `spellBonus` | percent | 4 | 7 ~ 40 | I01C, I01K, I026, I028 |
| `physicalBonus` | percent | 3 | 7 ~ 15 | I00I, I00O, I00Y |
| `allStatsGrowth` | flat | 3 | 1 ~ 4 | I00Q, I00W, I02C |
| `attackInterval` | seconds | 3 | -0.2 ~ -0.1 | I00S, I01B, I029 |
| `cooldownCap` | flat/percent | 2 | -20 ~ 5 | I00H, I013 |
| `armorPenetration` | flat/percent | 2 | 10 ~ 25 | I00I, I014 |
| `agilityGrowth` | flat | 2 | 3 ~ 4 | I00R, I01T |
| `strengthGrowth` | flat | 2 | 2 ~ 4 | I01D, I02B |
| `lifesteal` | flat/percent | 2 | 5 ~ 25 | I02O, I108 |
| `critChance` | percent | 1 | 10 | I00I |
| `manaRegen` | flat | 1 | 10 | I010 |
| `critResist` | flat | 1 | -50 | I016 |
| `hpRegen` | flat | 1 | 50 | I018 |
| `physicalResist` | percent | 1 | 15 | I01A |
| `attackGrowth` | flat | 1 | 3 | I01O |
| `luck` | flat | 1 | 1 | I023 |
| `spellPenetration` | percent | 1 | 10 | I028 |

## 未进入 attrs 的公式行

带 `x`、额外 `+` 或中文变量的行。按要求不建模，保留在 `ubertip` 里。

| 物品 | 行 |
|---|---|
| I00S | 主属性+10x散华计数 |
| I00S | 暴击伤害+5%x散华计数 |
| I00S | 物理加成+15%+2%x散华计数 |
| I00S | 神性+3x散华计数 |

## 自定义计数器行

例如 `「谣言」+1`，不是通用属性。保留在 `ubertip` 里。

| 物品 | 行 |
|---|---|
| I00E | 「谣言」+1 |
| I02D | 「谣言」+1 |
| I02E | 「谣言」+1 |
| I02F | 「谣言」+1 |
| I02G | 「谣言」+1 |
| I02H | 「谣言」+2 |
| I02I | 「谣言」+1 |
| I02J | 「谣言」+1 |
| I02K | 「谣言」+2 |
| I02L | 「谣言」+3 |
| I02M | 「谣言」+5 |

## 没有属性的物品

| 物品 | 名称 | pack |
|---|---|---|
| I000 | 任务：毛玉剿灭 | quest |
| I001 | 对话（祸） | quest |
| I002 | 对话（村长） | quest |
| I003 | 任务：采花 | quest |
| I00E | [未完成]SSR:小丘比[0格][卡池] | cards |
| I01L | R:闪光-亚丝娜[初始] | cards |
| I01X | R:玛娜莉亚的龙姬-古蕾雅[初始] | cards |
| I01Y | R:神影依-米德拉什[初始] | cards |
| I02D | R:「绝交律之谣」 | cards |
| I02E | R:「通灵神社之谣」 | cards |
| I02F | R:「猫头鹰幸运水之谣」 | cards |
| I02G | R:「无名氏之谣」 | cards |
| I02H | SR:「记忆博物馆之谣」 | cards |
| I02I | R:「Chelationland之谣」 | cards |
| I02J | R:「受信吊坠之谣」 | cards |
| I02K | SR:「神滨圣女之谣」 | cards |
| I02L | SSR:「万年樱之谣」 | cards |
| I02M | UR:「万年樱之谣」柊樱子 | cards |

## 约定

1. 物品数据表不放中文；中文只出现在 `attr.lua`（属性显示名）和 text 表。
2. `attrs` 的 key 是规范英文名，值默认是数字；带 `%` 的写成字符串，
   例如 `attackSpeed = "20%"`，因为同一个 key 可能同时出现固定值和百分比。
3. 源表是 `table/*.csv`；`<pack>.csv` 一行一件装备，
   属性列的顺序和是否合法由 `attr.csv` 决定。
4. 空单元格表示没有这一项；`description` 留空表示与 `ubertip` 相同。
5. `attr.lua` 的 `type` 决定写值方式：`integer` 用 `SaveInteger`，`real` 用 `SaveReal`；
   `percent` 只表示值后面可能带 `%`，去掉 `%` 后仍按 `type` 写。
   整型属性写小数会被 JASS 截断，转换器会把这种情况列进「类型冲突」。

