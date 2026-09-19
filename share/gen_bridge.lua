#!/usr/bin/env luajit

-- gen_bridge.lua
-- Summary: Generates project-specific bridge.lua with embedded API metadata.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local function read_file(p)
    local f = io.open(p, "r")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
end

local function parse_decl(l)
    l = l:match("^%s*(.-)%s*$")
    l = l:gsub(";%s*$", "")
    local bp = l:match("^(.+)%s*%(")
    if not bp then return nil end
    local n = bp:match("([%a_][%w_]*)%s*$")
    if not n then return nil end
    local rt = bp:sub(1, -(#n + 1)):match("^%s*(.-)%s*$")
    local ps = l:match("%((.+)%)")
    local ps_t = {}
    if ps and ps ~= "void" and ps ~= "" then
        for p in ps:gmatch("[^,]+") do
            p = p:match("^%s*(.-)%s*$")
            local pn = p:match("([%a_][%w_]*)%s*$")
            local pt
            if pn then
                pt = p:sub(1, -(#pn + 1)):match("^%s*(.-)%s*$")
            else
                pt = p
                pn = ""
            end
            table.insert(ps_t, {type = pt, name = pn})
        end
    end
    return n, rt, ps_t
end

local function parse_cdef(c)
    local fs = {}
    for l in c:gmatch("[^\r\n]+") do
        l = l:match("^%s*(.-)%s*$")
        if l ~= "" and not l:match("^//") and not l:match("^/%*") then
            local n, rt, p = parse_decl(l)
            if n and n:match("^kc_%w+") then
                table.insert(fs, {name = n, ret_type = rt, params = p})
            end
        end
    end
    return fs
end

local function esc(s)
    return s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
end

local kclib_dist_dir, arch, platform, template_path, out_path = arg[1], arg[2], arg[3], arg[4], arg[5]
local libs = {}
for i = 6, #arg do table.insert(libs, arg[i]) end

local api = {libraries = {}}

for _, lib in ipairs(libs) do
    local cdef_path = kclib_dist_dir .. "/" .. lib .. ".c/" .. arch .. "/" .. platform .. "/lib" .. lib .. ".cdef"
    local cdef = read_file(cdef_path)
    if cdef then
        local fs = parse_cdef(cdef)
        local lib_parts = {}
        table.insert(lib_parts, '    ["' .. lib .. '"] = {')
        table.insert(lib_parts, '      functions = {')
        for _, f in ipairs(fs) do
            table.insert(lib_parts, '        {')
            table.insert(lib_parts, '          name = "' .. esc(f.name) .. '",')
            table.insert(lib_parts, '          ret_type = "' .. esc(f.ret_type) .. '",')
            table.insert(lib_parts, '          params = {')
            for _, p in ipairs(f.params) do
                table.insert(lib_parts, '            {')
                table.insert(lib_parts, '              type = "' .. esc(p.type) .. '",')
                table.insert(lib_parts, '              name = "' .. esc(p.name) .. '",')
                table.insert(lib_parts, '            },')
            end
            table.insert(lib_parts, '          },')
            table.insert(lib_parts, '        },')
        end
        table.insert(lib_parts, '      },')
        table.insert(lib_parts, '    },')
        api.libraries[lib] = table.concat(lib_parts, "\n")
    end
end

local lib_order = {}
for _, l in ipairs(libs) do if api.libraries[l] then table.insert(lib_order, l) end end
table.sort(lib_order)

local parts = {}
for _, l in ipairs(lib_order) do table.insert(parts, api.libraries[l]) end
local bridge_api_str = table.concat(parts, "\n")

local template = read_file(template_path)
local output = template:gsub("@BRIDGE_API_LIBRARIES@", bridge_api_str)

local f = io.open(out_path, "w")
f:write(output)
f:close()