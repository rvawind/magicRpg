# baseItem 源表

> 所在层级：`magic/`（本项目专有实现）。`core/` 是第三方运行时与公用层，边界见 [`../../../../README.md`](../../../../README.md)。

这里是装备数据的源表。`../data/*.lua`、`../text/*.lua`、`../report.md`
都由本目录生成，不要手改。

属性定义不在这里，在 `magic/map/attr/attr.csv`（地图级注册表）。

```
python -I tools/ini2baseitem.py           # CSV -> Lua
python -I tools/ini2baseitem.py export --ini <w3x2lni导出的item.ini>    # item.ini -> CSV（仅初始化，会拒绝覆盖）
```

## 文件

| 文件 | 内容 |
|---|---|
| `<pack>.csv` | 一个装备包的数据，一行一件装备 |
| `<pack>.text.csv` | 同一个包的文本，按 `code` 与数据表对应 |

一个包 = 一对文件。删掉 `foo.csv` 和 `foo.text.csv`，再跑一次生成，
`data/foo.lua`、`text/foo.lua` 会被自动删除。

## <pack>.csv

第一列固定是 `code`，然后是固定列：

`parent, level, icon, class, hotkey, hp, usable, file, cooldown,
cost.gold, cost.lumber, stock.max, stock.regen, button.x, button.y`

后面跟属性列，**列名就是 `magic/map/attr/attr.csv` 的 key，顺序也按它**。
表头里出现注册表没有的列会直接报错。

- 空单元格 = 没有这一项
- 百分比写 `20%`，普通数值写 `20`
- `integer` 属性只能写整数；写成 `20%` 或 `20.5` 会报错

## <pack>.text.csv

`code, name, tip, ubertip, description`

- `description` 留空 = 与 `ubertip` 相同
- 生成报告会拿 `ubertip` 反解属性，与数据表对不上会列在「文本与数据不一致」

## Excel 注意事项

- 保存时选 **「CSV UTF-8（逗号分隔）」**；普通「CSV（逗号分隔）」是 GBK，
  生成器也能读，但 git 里会显示为乱码。
- 不要改动列名、不要删除 `code` 列、不要插入合并单元格。
- 百分比单元格显示为 `20%`，保存回去仍是 `20%`；不要手动改成 `0.2`。
