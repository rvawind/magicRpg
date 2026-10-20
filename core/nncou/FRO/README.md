# core/nncou/FRO/

FRO 专用的公用功能。

这里的代码沿用自 FRO 底图，服务 FRO 自己的聊天框和刷怪逻辑，**不是 NNCou 通用层的一部分**。`magic/` 里的新玩法不要依赖这里；需要通用能力时放到上一层 [`core/nncou/`](../README.md)。

> 当前仓库内没有对这两个库的 `include` 引用。它们要生效，需要地图主脚本或 GUI 触发器生成的脚本显式包含；文件放在 `jass/nncou/FRO/` 下不等于会自动编译。

## 文件

| 文件 | library | 作用 |
|---|---|---|
| `PlayerMsg.j` | `FroMsg` | 本地玩家的聊天框/消息队列，支持文字、静态图片和模型动画 |
| `PlayerMsg.cfg` | — | `FroMsg_*` 函数名清单 |
| `RushSystem.j` | `RushSystem` | 按回合/玩家刷怪，支持每波单位类型、技能和 BOSS 标记 |
| `RushSystem.cfg` | — | `RushSystem_*` 函数名清单 |

## PlayerMsg

在游戏界面左下角维护一个全局消息容器：

- 最多 20 条消息；新消息在最下方，旧消息向上推，超出容器最大高度后隐藏；
- 默认显示 10 秒，淡出 1 秒，每 0.1 秒更新一次；
- 每条消息可以是纯文字、文字 + 静态贴图，或文字 + 动态模型；
- 容器宽度、最大高度、行高、图片尺寸、间距、字体都可以在运行时调整；
- 基于 `DzFrame*` 界面 API，`FroMsg` 依赖 `BzAPI` 和 `LBKKAPI`。

`public function` 在 `library FroMsg` 里声明后，vJass 编译时会自动加上库名前缀：库内写 `ShowMessage`，外部（含 GUI）看到的是 `FroMsg_ShowMessage`。下面列的是外部名：

| 外部名 | 说明 |
|---|---|
| `FroMsg_ShowMessage(msg, imgPath, imgFlag)` | 显示文字；`imgPath` 非空时附带静态贴图，`imgFlag` 为是否平铺（0/1） |
| `FroMsg_ShowGifMessage(msg, modelPath, modelType, flag, animateIndex, isLoop, gifSize)` | 显示文字 + 动态模型；`modelType`、`flag` 透传给 `DzFrameSetModel`，`gifSize` 是相对缩放 |
| `FroMsg_SetFont(path, size, flag)` | 字体路径、大小、样式（0 普通 / 1 粗体 / 2 斜体 / 3 粗斜体） |
| `FroMsg_SetBoxWidth(width)` | 消息容器宽度 |
| `FroMsg_SetBoxMaxHeight(height)` | 消息容器最大高度 |
| `FroMsg_SetLineHeight(height)` | 单行文字高度 |
| `FroMsg_SetImageSize(width, height)` | 静态图片尺寸 |
| `FroMsg_SetPadding(padding)` | 消息之间的间距 |

GUI 分类为 `TC_FRO`。`PlayerMsg.cfg` 里的函数名是触发器编辑器看到的入口，改名或新增时 `.j`、`.cfg` 和函数上方的 `[标签]` 注释要一起改。

## RushSystem

按「玩家 + 回合」创建刷怪计时器，默认每 0.8 秒出一只：

| 函数 | 说明 |
|---|---|
| `RushSystem_SetTypeBase(round, unitType)` | 设置该回合的默认单位类型 |
| `RushSystem_SetCountBase(round, value)` | 设置该回合的默认数量；回合数量为 0 时回退到 `countBase[0]` |
| `RushSystem_SetRushMonsterEx(round, start, end, unitType)` | 显式指定第 `start` 到 `end-1` 只怪的单位类型（`start >= 1`，`end > start`） |
| `RushSystem_AddRushAbility(round, abilityId)` | 给该回合的每只怪附加一个技能 |
| `RushSystem_SetBoss(round, unitType)` | 把该回合标记为 BOSS 回合 |

两种刷怪模式：

- 普通模式：按 `SetCountBase` 的数量逐只创建 `SetTypeBase` 指定的单位；
- 显式模式：调用过 `SetRushMonsterEx` 后，按 1、2、3… 的槽位依次取单位类型，遇到空槽结束。

刷出的单位固定属于 `Player(5)`（0-based），位置取 `bornX/bornY/face` 数组。

### 这个模块目前是半成品

- `Rush` 是 `private`，而且没有调用方——没有「开始某一回合」的公开入口；
- `bornX`、`bornY`、`face` 没有设置函数，当前只能刷在 `(0, 0)`、面向 0；
- `CreateBoss` 是空函数，`SetBoss` 只会标记回合，不会真的创建 BOSS；
- `AddRushAbility` 是 `public`，但没有写进 `RushSystem.cfg`，GUI 里看不到。

如果之后要启用它，先补这些缺口，再决定它对哪些玩家/回合生效。不要把它当成现成的完整刷怪系统。

## 编译与 include

`core/nncou/FRO/*` 同步后对应 `jass/nncou/FRO/*`：

```bash
bash tools/sync_to_kkwe.sh
```

在编译树上这样引用：

```jass
#include "nncou\\FRO\\PlayerMsg.j"
#include "nncou\\FRO\\RushSystem.j"
```

`PlayerMsg.j` 自己会 include `BlizzardAPI.j` 和 `KKAPI.j`，这两个在编译树根部，不要写成 `nncou\\...`。

## GUI 配置

- `PlayerMsg.cfg` / `RushSystem.cfg`：每行一个对外函数名，供 YDWE 触发器编辑器加载；这里用的是编译后的外部名（`FroMsg_*` / `RushSystem_*`）；
- `PlayerMsg.j` 里的 `[函数名] title/description/category/args` 注释块：定义 GUI 条目和参数；这里用的是库内短名，vJass 会自动补库名前缀；
- 分类 `TC_FRO` 需要在 WE 的触发器分类里已经存在。

`PlayerMsg.cfg` 里的 `FroMsg_SetBoxMaxHeight` 对应库内的 `SetBoxMaxHeight`。`.cfg` 用编译后的外部名，函数上方的注释标签用库内短名；改名时 `.j`、`.cfg` 和标签要一起改。

## 修改约定

- 只放 FRO 专用的逻辑；通用能力放 [`../`](../README.md)，本项目玩法放 [`magic/`](../../../magic/README.md)。
- 对外函数名和 `.cfg` 是 GUI 的契约，改名要同步改 `.cfg`、注释标签和调用方。
- 改动前确认主脚本确实 include 了对应文件；没被 include 的改动不会进入编译结果。
