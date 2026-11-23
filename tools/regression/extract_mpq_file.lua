-- 从地图 MPQ 中提取单个文件（只读，用于分析 map 内二进制数据）
-- 用法（w3x2lni-lua.exe 运行）：
--   w3x2lni-lua.exe tools\regression\extract_mpq_file.lua <地图> <内部文件路径> <输出文件>
local W2L_PKG = os.getenv('W2L_PKG')
if not W2L_PKG or W2L_PKG == '' then
    W2L_PKG = [[C:\Users\admin\Documents\WE\KKWE_nncouVer1.5.7.1\plugin\w3x2lni_zhCN_v2.7.3]]
end
package.path = W2L_PKG .. '\\script\\?.lua;' .. W2L_PKG .. '\\script\\?\\init.lua;' .. W2L_PKG .. '\\script\\?\\?.lua;' .. package.path
package.cpath = W2L_PKG .. '\\bin\\?.dll;' .. package.cpath

local fs = require 'bee.filesystem'
local storm = require 'ffi.stormlib'

local SRC = assert(arg[1], 'missing arg1: map')
local NAME = assert(arg[2], 'missing arg2: inner file path')
local OUT = assert(arg[3], 'missing arg3: output file')

local ar = assert(storm.open(fs.path(SRC), true), 'open map failed')
local buf = ar:load_file(NAME)
ar:close()
assert(buf, 'file not found in map: ' .. NAME)
local f = assert(io.open(OUT, 'wb'))
f:write(buf)
f:close()
print('extracted', NAME, #buf, 'bytes ->', OUT)
