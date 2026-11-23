-- 从地图 MPQ 按前缀提取导入文件（只读源图；用于调研现成 UI 素材，如 ui\pk\*）
-- 用法（w3x2lni bin 目录下）：
--   w3x2lni-lua.exe extract_import.lua <源地图> <输出目录> <前缀(可选，如 ui\pk\)>
local W2L_PKG = os.getenv('W2L_PKG')
if not W2L_PKG or W2L_PKG == '' then
    W2L_PKG = [[C:\Users\admin\Documents\WE\KKWE_nncouVer1.5.7.1\plugin\w3x2lni_zhCN_v2.7.3]]
end
package.path = W2L_PKG .. '\\script\\?.lua;' .. W2L_PKG .. '\\script\\?\\init.lua;' .. W2L_PKG .. '\\script\\?\\?.lua;' .. package.path
package.cpath = W2L_PKG .. '\\bin\\?.dll;' .. package.cpath

local fs = require 'bee.filesystem'
local storm = require 'ffi.stormlib'

local SRC = assert(arg[1], 'missing arg1: source map')
local OUTDIR = assert(arg[2], 'missing arg2: output dir')
local PREFIX = (arg[3] or ''):gsub('/', '\\'):lower()

local src = assert(storm.open(fs.path(SRC), true), 'open source map failed')
local lf = assert(src:load_file('(listfile)'), 'no listfile')
local count, total = 0, 0
for name in lf:gmatch('[^\r\n]+') do
    local n = name:gsub('^\239\187\191', ''):gsub('^%s+', ''):gsub('%s+$', '')
    local key = n:lower()
    if n ~= '' and (PREFIX == '' or key:sub(1, #PREFIX) == PREFIX) then
        local buf = src:load_file(n)
        if buf then
            local rel = n:gsub('\\', '/')
            local path = fs.path(OUTDIR) / fs.path(rel)
            fs.create_directories(path:parent_path())
            local f = assert(io.open(path:string(), 'wb'))
            f:write(buf)
            f:close()
            count = count + 1
            total = total + #buf
            print(string.format('extract %-48s %8d bytes', n, #buf))
        else
            print('MISS', n)
        end
    end
end
print('done:', count, 'files,', total, 'bytes ->', OUTDIR)
