# core/nncou/

地图侧公用层：供 `magic/` 和 GUI 触发器共同使用的 JASS/vJass 能力。

它在 `core/` 下，但**不是 YDWE 代码**，也不属于某个具体关卡。和 `magic/` 的区别是复用范围：这里的能力换一张地图也能原样使用。

> 归属：多数文件沿用自 NNCou / FRO 底图，`BossChargeSystem*` 是本项目新增的公用能力，具体以文件注释和提交记录为准。GUI 触发器按函数名直接引用这里的函数，**改名前先搜调用方**。

## 边界

- 其他地图/玩法能原样复用 → 放这里；
- 只对本项目的房间、BOSS、奖励、数值有意义 → 放 `magic/`；
- YDWE / 平台 / Blizzard 的原始代码 → 放 `core/` 对应目录。

完整分层见根目录 [`README.md`](../../README.md)，专有实现见 [`magic/README.md`](../../magic/README.md)。

## 文件

### 基础与聚合

| 文件 | library | 作用 |
|---|---|---|
| `NNCouInterface.j` | `NNCouInterface` | 公用入口：include 各子系统，并提供 GUI 用的 `NNCou*` 包装函数 |
| `NNCouInterface.cfg` | — | 上述包装函数的函数名清单 |
| `NNCouString.j` | `NNCouString` | 字符串查找、分割、按 key 取片段 |
| `NNCouHDSystem.j` | `NNCouHDSystem` | 按「单位 + 技能 ID」存护盾/自定义值（`NNCGetHd` / `NNCSetHd` / `NNCReduceHd`） |
| `NNCouMission.j` | `NNCouMission` | 任务标题、描述、计数、自定义句柄存取 |

### 战斗与单位

| 文件 | library | 作用 |
|---|---|---|
| `NNCouControllerSystem.j` | `NNSystemController` | 控制链、无法施法 buf、技能/命令屏蔽 |
| `NNCouCureSystem.j` | `NNSystemCurer` | 治疗效率/被疗效果 buf，乘法叠加；`CureUnit` 统一结算 |
| `DmgSyc.j` | `DmgSyc` | 伤害事件封装：延迟伤害、伤害组、伤害类型比较 |
| `MaxSpeed.j` | `MaxSpeed` | 移动速度修正与 `GetUnitMoveSpeedEx` |
| `NNCouPushSystem.j` | `NNCouPushSystem` | 击飞、升空、滞空与飞行高度控制 |
| `NNCouEnumRect.j` | `NNCouEnumRect` | 按矩形/线段范围枚举单位 |

### 表现与提示

| 文件 | library | 作用 |
|---|---|---|
| `NNCouEffect.j` | `NNCouEffect` | 单位淡入、淡出 |
| `NNCouWarning.j` | `NNCouWarning` | 圆形/矩形预警特效，模型路径可配置 |

### BOSS 冲锋

| 文件 | library | 作用 |
|---|---|---|
| `BossChargeSystem.j` | `BossChargeSystem` | 冲锋轨迹核心：直线、极坐标弧线、曲线、折返，带缓动与序列执行 |
| `BossChargeSystemInterface.j` | `BossChargeSys` | GUI 接口层：用 integer 句柄（`Segment` / `SegHandle`）封装 struct API |
| `BossChargeSystemInterface.cfg` | — | GUI 可调用的接口函数清单 |
| `BossChargeSystem_action.txt` | — | YDWE 自定义动作：标题、描述、分类、参数 |
| `BossChargeSystem_call.txt` | — | YDWE 自定义调用/条件：含返回值声明 |
| `BossChargeSystem_define.txt` | — | 触发器分类 `TC_NNCCS` 与参数选项（缓动、弧方向等） |

### 其他

| 文件 | library | 作用 |
|---|---|---|
| `GetSkillDmg.j` | `NNCouInitSkillDmg` | 编译期用 Lua/`slk` 读技能数据，生成技能伤害函数 |
| `FRO/PlayerMsg.j` | `FroMsg` | FRO 专用：消息框、GIF 消息；依赖 `BlizzardAPI` + `KKAPI` |
| `FRO/RushSystem.j` | `RushSystem` | FRO 专用：波次刷怪配置（未完成，见子目录 README） |
| `check.j` | `CheckSync` | 用 DzAPI 同步收集各玩家上报值并校验一致性 |
| `NNCouExtraAttr.j` | `ExtraAttr` | 旧版额外属性系统；与 `magic/extraAttr.j` 同名，仓库内没有显式 include 引用，实际维护以 `magic/extraAttr.j` 为准 |
| `_tmp_update.py` | — | 工程侧临时脚本，不同步到 KKWE |

`FRO/` 是 FRO 底图专用功能，不属于 NNCou 通用层；细节和遗留问题见 [`FRO/README.md`](FRO/README.md)。

## 依赖关系

```text
NNCouInterface
├─ NNCouString
├─ NNCouHDSystem
├─ NNCouControllerSystem
├─ NNCouMission ── NNCouString
├─ NNCouWarning
├─ NNCouPushSystem ── NNCouPoint
├─ NNCouCureSystem
├─ NNCouEnumRect
└─ NNCouPoint（不在本仓库）

DmgSyc / MaxSpeed ── NNCouInterface
BossChargeSystem ── NNCouPoint + NNCouMath（后两者不在本仓库）
BossChargeSys ── BossChargeSystem
FroMsg ── BlizzardAPI + KKAPI
```

`NNCouPoint.j`、`NNCouMath.j` 以及 KKWE 里的 `Mission/` 等文件没有收进本仓库，编译时需要 KKWE 的 `jass/nncou/` 已存在这些文件。不要为了补全这里再复制一份，否则容易出现两份不同步的实现。

## 编译与同步

仓库路径和编译路径不同，`core/nncou/` 在编译树上对应 `jass/nncou/`：

```bash
bash tools/sync_to_kkwe.sh
```

例外映射（以 [`tools/sync_to_kkwe.sh`](../../tools/sync_to_kkwe.sh) 为准）：

| 仓库路径 | 同步后路径 |
|---|---|
| `core/nncou/*.j` | `jass/nncou/*.j` |
| `core/nncou/BossChargeSystem.j` | `jass/nncou/BossChargeSystem/BossChargeSystem.j` |
| `core/nncou/BossChargeSystemInterface.j` / `.cfg` | `jass/nncou/BossChargeSystem/` |
| `core/nncou/_tmp_update.py` | 不同步 |
| `*.md`（含本文件） | 不同步（文档留在仓库） |

所以 `#include` 写编译后路径：

```jass
#include "nncou\\NNCouInterface.j"
#include "nncou\\BossChargeSystem\\BossChargeSystem.j"
```

新文件沿用现有的头文件保护写法：

```jass
#ifndef FooIncluded
#define FooIncluded
#include "nncou\\NNCouInterface.j"
#endif
```

## GUI 接口

`.cfg`、`_action.txt`、`_call.txt`、`_define.txt` 是一组：YDWE 触发器编辑器靠它们显示函数、动作、参数和分类。增加或重命名一个 GUI 可调用的函数时，要同时更新对应的 `.cfg` 与 `.txt`；只改 `.j` 会出现「触发器里找不到函数」或参数对不上。

目前只有 BOSS 冲锋系统提供完整的一套 GUI 定义（分类 `TC_NNCCS`）。其他模块的 `.cfg` 是函数名清单。

## 修改约定

- 库名用 camelCase，不加 `udg_`；句柄用完置 `null`（见根目录 [`CLAUDE.md`](../../CLAUDE.md)）。
- `public function` / `NNCou*` 包装函数是给 `magic/` 和触发器用的 API，改名/改参数前先全局搜索调用方。
- 这里只放可复用的能力；某个关卡专用的逻辑写到 `magic/`。
- 修改沿用自底图的文件时，在提交信息里说明改了什么、为什么，方便和 KKWE 里的原版对照。
- 少数旧文件注释里已有乱码（如 `NNCouEnumRect.j`），不影响编译；不要为了修注释整文件转码。
