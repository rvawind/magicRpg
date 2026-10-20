# magicRpg

《魔兽争霸 III》4 人合作地牢 Roguelike 地图的 JASS/vJass 源码工程。

核心循环：进入房间 → 清理怪物/交互 → 获得奖励 → 选择出口 → 推进 → 击败 BOSS → 进入新区域。

## 代码归属（先看这里）

仓库里的代码**不全是本项目原创**：

| 目录 | 内容 | 归属 |
|---|---|---|
| `core/` | YDWE 运行时、JAPI、平台 API、Blizzard 声明、地图公用系统 | **第三方 + 公用层**；大量代码版权归 YDWE / 平台 / Blizzard 作者 |
| `magic/` | 房间、BOSS、章节、诅咒、奖励、装备等玩法实现 | **本项目专有** |

- `core/` 下 YDWE 及其生态的代码是作为**编译依赖**一并保存的，本项目不对其主张著作权；使用、修改、分发请遵循各原始项目的许可。
- 本项目新增或修改的公用代码集中在 `core/nncou/`；专有玩法放在 `magic/`。
- 不要因为某个文件在 `core/` 就默认它是本项目写的，也不要把专有逻辑写进 `core/`。

各层的详细边界和来源见 [`core/README.md`](core/README.md) 与 [`magic/README.md`](magic/README.md)。

### 本仓库的范围

这不是一棵可以独立编译的完整源码树，而是本项目的工作副本：

- 仓库保存本项目的源码，以及 `core/` 下的 YDWE/平台依赖；
- 底图里**未改动**的文件（例如 `Util/`、`NNCouPoint.j`、`NNCouMath.j`）仍在 KKWE 的 `jass/` 目录里，不在本仓库；
- 所以部分 `#include` 在本仓库内找不到目标文件，是正常的；编译在同步后的 KKWE `jass/` 树里进行。

## 目录

```text
magic-core/
├── core/                 第三方运行时 + 地图公用 API
│   ├── YDWE*.j           YDWE 运行时/插件（YDWE 作者）
│   ├── Base/             YDWE 基础库（YDWE 作者）
│   ├── japi/             YDWE JAPI 封装（YDWE 作者）
│   ├── system/           Blizzard 的 common.j / blizzard.j
│   ├── *API.j            Blizzard / Dz / KK 平台接口
│   └── nncou/            地图公用系统与公用 API
├── magic/                本项目专有实现
│   ├── map/area/         房间/区域框架（网格、槽位、进出、传送、怪物房）
│   ├── map/boss/         BOSS
│   ├── map/chapter/      章节/波次
│   ├── map/curse/        诅咒
│   ├── map/reward/       奖励/祭坛
│   ├── map/ui/           UI
│   ├── map/timer/        计时器
│   ├── map/monster/      怪物组
│   ├── map/attr/         属性注册表
│   └── map/equip/        装备包管线
├── tools/                同步与数据转换脚本
├── debug.j               调试日志（编译到 jass/nncou/debug.j）
├── monster.j             怪物池参考副本（实际维护在 magic/monster.j）
└── extraAttr.j           额外属性参考副本（实际维护在 magic/extraAttr.j）
```

## `core/` 与 `magic/` 的边界

判断一段代码该放哪：

- **其他地图或玩法也能原样复用** → `core/nncou/`（公用能力）；
- **只对本项目的房间、奖励、关卡、数值有意义** → `magic/`（专有实现）；
- **YDWE / 平台 / Blizzard 的原有代码** → `core/` 对应目录，尽量不改；确需修改时单独提交并说明原因。

`core/nncou/` 不是 YDWE 代码，它是地图侧的公用层：既有沿用自底图的通用系统，也有本项目新增的公用 API。它和 `magic/` 同属项目侧代码，只是服务范围更广；具体哪些是底图原有、哪些是本次新增，以文件注释和提交记录为准。

## include 路径约定（容易看错）

源码在仓库里的路径，和编译器看到的路径**不一样**。编译时以 YDWE 的 `jass/` 为根：

| 仓库路径 | 编译后路径 |
|---|---|
| `core/*` | `jass/*` |
| `magic/*` | `jass/nncou/magic/*` |
| `debug.j` | `jass/nncou/debug.j` |

因此 `#include` 写的是**编译后路径**，不是仓库路径。例如：

```jass
// 文件实际在 magic/map/area/core/data.j
#include "nncou\\magic\\map\\area\\core\\data.j"
```

- 在仓库里按 `nncou\magic\...` 找文件是找不到的，这是正常的；用 `tools/sync_to_kkwe.sh` 同步到 `jass/` 后才会成立。
- 根目录的 `debug.j` 编译到 `jass/nncou/debug.j`，所以从 `magic/` 引用它写 `#include "nncou\\debug.j"`。
- 源码里的 `\\` 是 Windows 路径分隔符在 JASS 字符串中的写法，实际就是一个 `\`。
- `core/nncou/BossChargeSystem.j` 等少数文件有额外的目录映射，以 [`tools/sync_to_kkwe.sh`](tools/sync_to_kkwe.sh) 的 `map_rel` 为准。

## 构建与同步

本工程不是直接编译的源码目录；WE/YDWE 编译的是同步后的 `jass/` 目录。

```bash
bash tools/sync_to_kkwe.sh              # 同步改动到 KKWE 的 jass 目录
bash tools/sync_to_kkwe.sh --dry-run    # 只查看将复制哪些文件
bash tools/sync_to_kkwe.sh --all        # 同步所有有差异的已映射文件（谨慎）
```

目标目录默认指向本地 KKWE 的 `jass/` 目录，可用环境变量 `KKWE_JASS` 覆盖。

装备数据管线：

```bash
python -I tools/ini2baseitem.py          # CSV -> Lua
python -I tools/ini2baseitem.py export --ini <w3x2lni导出的item.ini>   # item.ini -> CSV（仅初始化，拒绝覆盖）
```

## 文档

- [`core/README.md`](core/README.md)：第三方/公用层的来源与归属
- [`magic/README.md`](magic/README.md)：本项目代码的目录与 include 约定
- [`magic/map/attr/README.md`](magic/map/attr/README.md)：属性注册表
- [`magic/map/equip/baseItem/table/README.md`](magic/map/equip/baseItem/table/README.md)：装备 CSV 源表
- [`magic/介绍_v2.txt`](magic/介绍_v2.txt)：玩法设计
- [`magic/计划.md`](magic/计划.md)、[`magic/测试.md`](magic/测试.md)：开发计划与验收清单
