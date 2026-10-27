# 本地预编译校验（pjass，不替代 YDWE）

WE/YDWE 编译的是 `KKWE_nncouVer1.5.7.1\jass`，本工程只是源码。改完 `.j` 后先用本工具做一次
语法/跨库符号检查，可以避免把「未定义函数」这类低级错误带到作者那里。

## 一次性准备

`clijasshelper.exe` 调用 `plugin\jasshelper\pjass.exe`，但 KKWE 只带了 `plugin\pjass\pjass-latest.exe`：

```bash
cp /c/Users/admin/Documents/WE/KKWE_nncouVer1.5.7.1/plugin/pjass/pjass-latest.exe \
   /c/Users/admin/Documents/WE/KKWE_nncouVer1.5.7.1/plugin/jasshelper/pjass.exe
```

用完可以删掉这个副本（JassHelper 还会生成 `backups/`、`logs/`、`jasshelper.conf`，都可删）。

## 使用

1. 先在 YDWE 里保存一次地图，生成/刷新 `KKWE_nncouVer1.5.7.1\logs\inputwar3map.j`；
2. 仓库根目录执行：

```bash
python tools/precompile_check/build_harness.py
MSYS_NO_PATHCONV=1 cmd.exe /c 'C:\Users\admin\Documents\WE\magic-core\tools\precompile_check\run.bat'
tail -5 tools/precompile_check/out/compile.log
```

看到 `Success!` 与 `EXIT=0` 即通过。

## 它做了什么

- 取 `inputwar3map.j` 中 `DebugLogger` 之前的 GUI 部分（含 `gg_rct_*` 全局）；
- 合成 20 个房间矩形 + 16 个门洞模板矩形的全局变量（真实地图由作者创建）；
- 未改动的库直接拷贝已编译结果；
- 改动过的库使用工程内源码（清单见 `build_harness.py` 的 `SOURCES`）；
- 拼成 `out/harness.j` 交给 `clijasshelper --scriptonly`。

## 注意

- 新增/重命名库时，要同步更新 `SOURCES` 与 `REPLACED`；
- 它只验证语法与符号，**不验证运行逻辑**，也不能替代 YDWE 编译与游戏内测试；
- YDWE 每次重新生成 `inputwar3map.j`，所以库的位置是运行时查找的，不要写死行号。
