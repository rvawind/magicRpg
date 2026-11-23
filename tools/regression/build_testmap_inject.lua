-- 测试图注入版构建脚本（支持「替换」与「新增」导入文件；源图只读）
--
-- 目的：把尚未导入生产地图的新贴图（如 ui\slab.blp、ui\gold.blp）或改过的 FDF
--       注入「测试图副本」做游戏内验证，避免先改作者的生产地图。
--
-- 用法（在 w3x2lni 的 bin 目录下运行）：
--   w3x2lni-lua.exe <本脚本> <源地图> <编译产物 war3map.j> <输出测试图> [名=本地文件 ...]
--
--   例：
--   w3x2lni-lua.exe tools\regression\build_testmap_inject.lua ^
--       "C:\Users\admin\Documents\WE\幻想之战-全模型\new0.1 26.11.15.w3x" ^
--       "tools\precompile_check\out\harness_test_out.j" ^
--       "testmaps\11-16_probe_inject.w3x" ^
--       "ui\slab.blp=D:\tmp\slab.blp" "ui\gold.blp=D:\tmp\gold.blp"
--
--   - 每个「名=本地文件」对：名是 MPQ 内路径（反斜杠），路径可新增也可覆盖源图已有文件；
--   - war3map.j 固定替换为 arg2 编译产物；
--   - 源图只读打开，绝不回写；输出 = 源图 512B HM3W 头 + 重建的 MPQ；
--   - 脚本末尾会重开输出图，逐个校验注入文件字节与输入一致。
--
-- 与 tools/regression/build_testmap.lua 的关系：本脚本不替代它；官方测试图构建仍用
-- build_testmap.lua，只有「需要注入新导入资源」时才用本脚本。

local W2L_PKG = os.getenv('W2L_PKG')
if not W2L_PKG or W2L_PKG == '' then
    W2L_PKG = [[C:\Users\admin\Documents\WE\KKWE_nncouVer1.5.7.1\plugin\w3x2lni_zhCN_v2.7.3]]
end
package.path = W2L_PKG .. '\\script\\?.lua;' .. W2L_PKG .. '\\script\\?\\init.lua;' .. W2L_PKG .. '\\script\\?\\?.lua;' .. package.path
package.cpath = W2L_PKG .. '\\bin\\?.dll;' .. package.cpath

local fs = require 'bee.filesystem'
local storm = require 'ffi.stormlib'

local SRC  = assert(arg[1], 'missing arg1: source map')
local NEWJ = assert(arg[2], 'missing arg2: compiled war3map.j')
local FINAL = assert(arg[3], 'missing arg3: output test map')

local function readfile(path)
    local f = assert(io.open(path, 'rb'), 'cannot open ' .. path)
    local b = f:read('*a')
    f:close()
    return b
end

local t0 = os.clock()
local newscript = readfile(NEWJ)
assert(#newscript > 1000, 'compiled war3map.j looks too small')

-- arg4.. 解析为 名=本地文件
local inject = {}          -- key(lower) -> { name, bytes, size }
local injectOrder = {}
for i = 4, #arg do
    local spec = arg[i]
    if spec and spec ~= '' then
        local name, path = spec:match('^([^=]+)=(.*)$')
        assert(name and path and #path > 0, 'bad inject spec (expect name=path): ' .. spec)
        name = name:gsub('/', '\\')
        local key = name:lower()
        if inject[key] then
            print('WARN duplicate inject target, last wins:', name)
        else
            injectOrder[#injectOrder + 1] = key
        end
        local bytes = readfile(path)
        assert(#bytes > 0, 'injected file is empty: ' .. path)
        inject[key] = { name = name, bytes = bytes, size = #bytes }
        print('inject:', name, '<-', path, '(', #bytes, 'bytes )')
    end
end
assert(#injectOrder > 0, 'missing arg4: at least one name=path inject spec is required')
print('new war3map.j bytes:', #newscript, ' inject targets:', #injectOrder)

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

-- 新增文件：源 listfile 里没有的话 append 到复制清单（WC3 按名 hash 索引，不依赖 listfile；
-- StormLib 重建 MPQ 时会自行处理 (listfile)）
local added = 0
for _, key in ipairs(injectOrder) do
    if not seen[key] then
        seen[key] = true
        names[#names + 1] = inject[key].name
        added = added + 1
        print('add new file:', inject[key].name)
    end
end
print('inject targets:', #injectOrder, ' new files:', added)

local tmpRaw = os.tmpname() .. '.mpq'
local out = assert(storm.create(fs.path(tmpRaw), #names + 8, false), 'create mpq failed')
local written, nJ = 0, 0
local used = {}
for _, name in ipairs(names) do
    local key = name:lower()
    local buf
    if key == 'war3map.j' then
        buf = newscript
        nJ = nJ + 1
    elseif inject[key] then
        buf = inject[key].bytes
        used[key] = true
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
assert(nJ == 1, 'expected exactly one war3map.j substitution')
for _, key in ipairs(injectOrder) do
    assert(used[key], 'inject target was not written: ' .. inject[key].name)
end
print('saved files:', written, ' war3map.j x' .. nJ)

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

-- 自校验：重开输出图，逐个比对注入文件字节
local chk = assert(storm.open(fs.path(FINAL), true), 'cannot reopen output map')
local bad = 0
for _, key in ipairs(injectOrder) do
    local t = inject[key]
    local got = chk:load_file(t.name)
    local equal = got and #got == t.size and got == t.bytes
    print('VERIFY ' .. t.name .. ': bytes=' .. (got and #got or -1) .. ' equal_to_input=' .. tostring(equal))
    if not equal then bad = bad + 1 end
end
chk:close()
assert(bad == 0, bad .. ' injected file(s) mismatch!')
print('OK final:', FINAL, string.format('%.1fs', os.clock() - t0))
