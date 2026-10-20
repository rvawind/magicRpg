# 属性注册表

> 所在层级：`magic/`（本项目专有实现）。`core/` 是第三方运行时与公用层，边界见 [`../../README.md`](../../README.md)。

`attr.csv` 是**地图级**属性定义，不属于任何一个装备包。装备、肉鸽奖励、
诅咒卡等系统都引用同一份定义；新增属性只在这里登记一次。

```
python -I tools/ini2baseitem.py           # attr.csv -> attr.lua（同时重建装备表）
python -I tools/ini2baseitem.py export --ini <w3x2lni导出的item.ini>    # item.ini -> CSV（仅初始化）
```

## 列

| 列 | 说明 |
|---|---|
| `key` | 代码里用的键名，英文 camelCase |
| `label` | 显示名，也是 `ubertip` 里出现的写法 |
| `jass` | JASS 侧 `StringHash("...")` 的字符串键；留空 = JASS 还没实现 |
| `type` | `integer` = `SaveInteger/LoadInteger`，`real` = `SaveReal/LoadReal` |
| `writer` | `attr` = `attr.j` 从 `Item` 累加进 `YDHT`；`loader` = 载入器直接写 `YDHT`；留空 = 没人写 |
| `percent` | `1` = 允许 `20%` 这种写法 |
| `unit` | `seconds`，缺省为空（flat） |
| `aliases` | 说明文本里的其它写法，用 `;` 分隔 |

`label` 和 `jass` 不是一回事，例如：

| key | label（文本里写的） | jass（JASS 里存的） |
|---|---|---|
| `expEfficiency` | 经验效率 | 经验增幅 |
| `cooldownReduction` | 冷却缩减 | 冷却减免 |
| `hpRegen` | 每秒回血 | 每秒回固定 |
| `hpRegenPercent` | 每秒回血% | 每秒回百分比 |
| `manaRegen` | 法力回复 | 每秒回蓝固定 |

`jass` 必须与 `attr.j` / `NNCouExtraAttr.j` 里 `StringHash(...)` 的字符串完全一致，
否则载入器写进去的值，游戏逻辑读不到。`type` 也必须与实际使用的
`SaveInteger/SaveReal` 一致。

## 三个哈希表

`attr.j` 里有三个哈希表，用途不同：

| 表 | 主键 | 内容 |
|---|---|---|
| `Item` | 物品 ID | 该物品提供哪些属性、各多少（定义） |
| `Skill` | 卡片 ID / 技能 ID | 卡片与动态技能互相对应 |
| `YDHT` | 单位 handle | 加起来以后的属性总值（运行时） |

`YDHT` 是逆天触发器专用的，GUI 动作「哈希表 - 保存整数」写的就是它。
**读取方可以是 `attr.j`，也可以是触发器**——例如触发器函数 `Exp` 里
「获取 [单位] loc_hero 的经验增幅」读的就是 `YDHT`。所以属性不一定非得
`attr.j` 认识，只要键一致，触发器就能读到。

`writer` 记录的是**谁负责把值写进 `YDHT`**：

- `attr`：`attr.j` 在拿到物品时把 `Item` 里的值累加到 `YDHT`。绝大多数属性属于这类。
  触发器照样可以读，不影响。
- `loader`：`attr.j` 不解析这个键，载入器必须直接写 `YDHT`；
  写进 `Item` 不会生效。目前是 `神性`——十罪卡片系统在读它。
- 留空：`jass` 也为空，没人写（`attackGrowth`、`spellPenetration`、`luck`），
  装备上的数值只用于展示；实现后填上 `jass` 和 `writer` 即可。

## 新增一个属性

1. 在 `attr.csv` 末尾加一行，填 `key / label / jass / type`。
2. 在 JASS 侧实现消费逻辑（`attr.j` 或对应系统），
   确认 `jass` 与 `StringHash(...)` 的字符串一致。
3. 跑一次生成器。

装备表的数据 CSV 会按注册表顺序自动带上新列——已有的包不需要手工加列。

## 注意

- 这里可以出现中文（`label`、`aliases` 本来就是中文），装备数据表不行。
- 同一个标签的百分比形态可能对应另一个 JASS 键：`每秒回血+1%` 会分流到
  `hpRegenPercent`（`每秒回百分比`），`每秒回血+50` 才是 `hpRegen`（`每秒回固定`）。
  同理 `法力回复+5%` 分流到 `manaRegenPercent`。
- 额外属性词缀（`ExtraAttr`）共用同一套键，也是写 `YDHT`；改键名时两边要一起改。
  `core/nncou/NNCouExtraAttr.j` 里还有一处旧写法 `createRealAttr("经验效率")`，
  与 `attr.j` 的 `经验增幅` 不一致；KKWE 目录下的 `nncou/magic/extraAttr.j` 已经改成
  `经验增幅`，以它为准。
- 不要把它挪进某个装备包目录；`baseItem` 只是消费者之一。
