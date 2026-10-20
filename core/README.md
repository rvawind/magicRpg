# core/

第三方运行时 + 地图公用 API 层。

> **本目录不是本项目的专有玩法实现。** 大量代码来自 YDWE 及其生态，版权归原作者；本项目只把它们作为编译依赖保存，不对其主张著作权。

## 内容与来源

| 路径 | 内容 | 来源 / 归属 |
|---|---|---|
| `YDWE*.j` | YDWE 运行时与插件（计时器、伤害、物品、字符串、寻路等） | YDWE 作者 |
| `Base/` | YDWE 基础库（公共全局量、哈希表/返回值兼容） | YDWE 作者 |
| `japi/` | YDWE JAPI 封装（对象、特效、单位、脚本） | YDWE 作者 |
| `system/ht/`、`system/rb/` | Blizzard 的 `common.j` / `blizzard.j` 声明 | Blizzard |
| `BlizzardAPI.j` | 平台 / Blizzard 原生接口声明 | Blizzard / 平台 |
| `DzAPI.j` | 网易对战平台 API | DzAPI 作者 |
| `KKAPI.j`、`KKPRE.j` | KK 平台 API | KK 作者 |
| `nncou/` | 地图公用系统与公用 API | 底图沿用 + 本项目新增的公用部分 |

> `core/` 不是完整的底图依赖集。`Util/`、`NNCouPoint.j`、`NNCouMath.j` 等未改动文件仍在 KKWE 的 `jass/` 树中；本仓库只保存本项目需要维护的那部分。

### `core/nncou/`

地图侧公用层，供 `magic/` 和 GUI 触发器共同使用。典型内容：

- `NNCouInterface.j`、`NNCouString.j` 等基础接口；
- `DmgSyc.j`、`NNCouWarning.j`、`NNCouCureSystem.j`、`NNCouPushSystem.j` 等通用系统；
- `NNCouPoint.j`、`NNCouMath.j`：接口依赖，本仓库未收录，仍在 KKWE 的 `jass/nncou/` 中；
- `BossChargeSystem.j` / `BossChargeSystemInterface.*`：BOSS 冲锋轨迹的公用能力（GUI 友好参数；同步后归入 `nncou/BossChargeSystem/`）。

它不是 YDWE 代码，但也不属于某个具体玩法——判断标准见下。

## 归属与修改约定

- `core/` 下 YDWE 及其生态的代码**不是本项目原创**。本仓库保存它们是为了让地图可编译；使用、修改、分发请遵循原始项目的许可。
- 本项目新增/修改的公用代码集中在 `core/nncou/`。改动第三方文件时，请在提交信息中注明改了什么、为什么。
- 专有玩法、数值、关卡、奖励逻辑不要写进 `core/`，放到 `magic/`。
- 判断标准：**其他地图/玩法能原样复用** → `core/nncou/`；**只对本项目有意义** → `magic/`。

## include 根

编译时 `core/` 映射到 YDWE `jass/` 的根目录，所以这里的 `#include` 直接写：

```jass
#include "YDWEBase.j"
#include "japi\\YDWEJapiScript.j"
#include "nncou\\NNCouInterface.j"
```

仓库路径与编译路径的完整对应见根目录 [`README.md`](../README.md)。
