# magic/

本项目的专有实现。`core/` 提供第三方运行时和公用 API，这里只放本项目的玩法、数据和配置。

## 目录

| 路径 | 内容 |
|---|---|
| `map/area/core/` | 房间框架：网格、槽位、进出、传送、怪物房、紧急穿越 |
| `map/area/config/` | 关卡配置（forest、dust） |
| `map/boss/` | BOSS 逻辑 |
| `map/chapter/` | 章节/波次 |
| `map/curse/` | 诅咒 |
| `map/reward/` | 奖励与祭坛 |
| `map/ui/` | 选择界面等 UI |
| `map/timer/` | 计时器 |
| `map/monster/` | 怪物组定义与筛选 |
| `map/attr/` | 地图级属性注册表 |
| `map/equip/` | 装备包管线（CSV -> Lua） |

根目录的 `monster.j`、`extraAttr.j` 是早期参考副本；实际维护的是 `magic/monster.j`、`magic/extraAttr.j`。

## include 路径为什么带 `nncou\`

仓库里的 `magic/` 在编译时会整体映射到 YDWE 的 `jass/nncou/magic/`。所以 `magic` 内部互相引用时，写的是**编译后路径**，不是仓库路径：

```jass
// 仓库：magic/map/area/core/data.j
// 编译后：jass/nncou/magic/map/area/core/data.j
#include "nncou\\magic\\map\\area\\core\\data.j"
```

几个容易看错的点：

- `nncou\` 不是仓库里的目录，是编译后的父目录；仓库里对应的是 `magic/...`。
- 根目录 `debug.j` 编译到 `jass/nncou/debug.j`，所以引用写 `#include "nncou\\debug.j"`。
- `core/` 下的文件在编译后位于 `jass/` 根，引用它们**不要**加 `nncou\magic\` 前缀。例如平台接口是 `#include "BlizzardAPI.j"`。
- 源码里的 `\\` 是 JASS 字符串中的 Windows 路径分隔符，实际就是一个 `\`。
- 少数文件在同步时有额外目录映射，以 [`tools/sync_to_kkwe.sh`](../tools/sync_to_kkwe.sh) 的 `map_rel` 为准。

## 约定

- 新增玩法只放 `magic/`；不要改 `core/` 里的第三方代码。确需改动时单独提交并说明原因。
- 数据与文本分离；`map/attr` 与 `map/equip` 的生成物不要手改，改 CSV 后重新跑生成器。
- 详细规则见 [`map/attr/README.md`](map/attr/README.md) 与 [`map/equip/baseItem/table/README.md`](map/equip/baseItem/table/README.md)。
