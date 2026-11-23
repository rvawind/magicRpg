-- 测试版地图构建脚本（spike 原型）
-- 用法（在 w3x2lni_zhCN_v2.7.3\bin 目录下）：
--   w3x2lni-lua.exe tools\regression\build_testmap.lua <源地图> <脚本文件> <输出地图>
--
-- 做了什么：
--   1) 用 w3x2lni 的 stormlib ffi 打开源地图（只读），按 (listfile) 全量读取文件；
--   2) 创建新 MPQ，逐文件写入，把 war3map.j 替换为传入的编译产物；
--   3) 读取源地图前 512 字节 HM3W 头 + 新 MPQ，写出测试版 .w3x。
--
-- 约束：
--   - 只读源地图，不写回；输出必须是独立测试版本文件（如 testmaps/11-08_test01.w3x）；
--   - 测试代码必须来自 JASS 编译产物，不允许手工拼脚本；
--   - 跳过 (listfile)/(attributes)/(signature)，由 StormLib 重建。

local pkg = (arg[0] or ''):gsub('\\[^\\]+$', '')
-- 允许从任意 cwd 调用：脚本所在目录的上一级找不到包时，用环境变量 W2L_PKG 指定
local W2L_PKG = os.getenv('W2L_PKG')
if not W2L_PKG or W2L_PKG == '' then
    W2L_PKG = [[C:\Users\admin\Documents\WE\KKWE_nncouVer1.5.7.1\plugin\w3x2lni_zhCN_v2.7.3]]
end
package.path = W2L_PKG .. '\\script\\?.lua;' .. W2L_PKG .. '\\script\\?\\init.lua;' .. W2L_PKG .. '\\script\\?\\?.lua;' .. package.path
package.cpath = W2L_PKG .. '\\bin\\?.dll;' .. package.cpath

local fs = require 'bee.filesystem'
local storm = require 'ffi.stormlib'

local SRC = assert(arg[1], 'missing arg1: source map')
local NEWJ = assert(arg[2], 'missing arg2: compiled war3map.j')
local FINAL = assert(arg[3], 'missing arg3: output test map')

local t0 = os.clock()
local srcAr = assert(storm.open(fs.path(SRC), true), 'open source map failed')
local lf = srcAr:load_file('(listfile)')
assert(lf, 'source map has no readable (listfile)')
local names, seen = {}, {}
local skip = { ['(listfile)'] = true, ['(attributes)'] = true, ['(signature)'] = true }
for name in lf:gmatch('[^\r\n]+') do
    local n = name:gsub('^\239\187\191', ''):gsub('^%s+', ''):gsub('%s+$', '')
    local key = n:lower()
    if n ~= '' and not skip[key] and not seen[key] then
        seen[key] = true
        names[#names + 1] = n
    end
end
print('source files:', #names)

local f = io.open(NEWJ, 'rb')
local newscript = f:read('*a')
f:close()
print('new war3map.j bytes:', #newscript)

local tmpRaw = os.tmpname() .. '.mpq'
local out = assert(storm.create(fs.path(tmpRaw), #names + 8, false), 'create mpq failed')
local written = 0
for _, name in ipairs(names) do
    local buf
    if name:lower() == 'war3map.j' then
        buf = newscript
    else
        buf = srcAr:load_file(name)
    end
    if buf then
        out:save_file(name, buf)
        written = written + 1
    else
        print('WARN cannot read', name)
    end
end
srcAr:close()
out:close()
print('saved files:', written, string.format('%.1fs', os.clock() - t0))

-- HM3W 头 + 新 MPQ = 测试版地图
local sf = io.open(SRC, 'rb')
local header = sf:read(512)
sf:close()
assert(header and #header == 512 and header:sub(1, 4) == 'HM3W', 'source map has no HM3W header')
local fin = io.open(FINAL, 'wb')
fin:write(header)
local mf = io.open(tmpRaw, 'rb')
local chunk
repeat
    chunk = mf:read(1024 * 1024)
    if chunk then fin:write(chunk) end
until not chunk
mf:close()
fin:close()
os.remove(tmpRaw)
print('final written:', FINAL, string.format('%.1fs', os.clock() - t0))
