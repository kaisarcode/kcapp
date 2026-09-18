#!/usr/bin/env lua

-- gen_bridge_api.lua
-- Summary: Generates bridge API metadata from kclib public headers.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function parse_declaration(line)
    line = line:match("^%s*(.-)%s*$")
    line = line:gsub(";%s*$", "")
    
    local before_paren = line:match("^(.+)%s*%(")
    if not before_paren then return nil end
    
    local name = before_paren:match("([%a_][%w_]*)%s*$")
    if not name then return nil end
    
    local ret_type = before_paren:sub(1, -(#name + 1))
    ret_type = ret_type:match("^%s*(.-)%s*$")
    
    local params_str = line:match("%((.+)%)")
    local params = {}
    if params_str and params_str ~= "void" and params_str ~= "" then
        for param in params_str:gmatch("[^,]+") do
            param = param:match("^%s*(.-)%s*$")
            local pname = param:match("([%a_][%w_]*)%s*$")
            local ptype
            if pname then
                ptype = param:sub(1, -(#pname + 1))
                ptype = ptype:match("^%s*(.-)%s*$")
            else
                ptype = param
                pname = ""
            end
            table.insert(params, {type = ptype, name = pname})
        end
    end
    
    return name, ret_type, params
end

local function parse_cdef(cdef_content)
    local functions = {}
    for line in cdef_content:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^//") and not line:match("^/%*") then
            local name, ret_type, params = parse_declaration(line)
            if name and name:match("^kc_%w+") then
                table.insert(functions, {
                    name = name,
                    ret_type = ret_type,
                    params = params
                })
            end
        end
    end
    return functions
end

local function escape_lua_string(s)
    return s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
end

local function generate_lua_table(api)
    local parts = {}
    table.insert(parts, "return {")
    table.insert(parts, "  version = 1,")
    table.insert(parts, "  libraries = {")
    
    for lib_name, lib_info in pairs(api.libraries) do
        table.insert(parts, '    ["' .. lib_name .. '"] = {')
        table.insert(parts, "      functions = {")
        for _, f in ipairs(lib_info.functions) do
            table.insert(parts, "        {")
            table.insert(parts, '          name = "' .. escape_lua_string(f.name) .. '",')
            table.insert(parts, '          ret_type = "' .. escape_lua_string(f.ret_type) .. '",')
            table.insert(parts, "          params = {")
            for _, p in ipairs(f.params) do
                table.insert(parts, "            {")
                table.insert(parts, '              type = "' .. escape_lua_string(p.type) .. '",')
                table.insert(parts, '              name = "' .. escape_lua_string(p.name) .. '",')
                table.insert(parts, "            },")
            end
            table.insert(parts, "          },")
            table.insert(parts, "        },")
        end
        table.insert(parts, "      },")
        table.insert(parts, "    },")
    end
    
    table.insert(parts, "  }")
    table.insert(parts, "}")
    return table.concat(parts, "\n")
end

local function generate_bridge_api(libs, kclib_dist_dir, arch, platform, output_path)
    local api = {
        version = 1,
        libraries = {}
    }

    for _, lib in ipairs(libs) do
        local cdef_path = kclib_dist_dir .. "/" .. lib .. ".c/" .. arch .. "/" .. platform .. "/lib" .. lib .. ".cdef"
        local cdef_content = read_file(cdef_path)
        if not cdef_content then
            -- Library not available for this target, skip it
            io.stderr:write("kcapp: skipping " .. lib .. " for " .. arch .. "/" .. platform .. " (no cdef)\n")
        else
            local functions = parse_cdef(cdef_content)
            api.libraries[lib] = {
                functions = functions
            }
        end
    end

    local output = "-- bridge_api.lua\n"
    output = output .. "-- Generated automatically from kclib public headers.\n"
    output = output .. "-- Do not edit manually.\n\n"
    output = output .. generate_lua_table(api)
    return write_file(output_path, output)
end

local kclib_dist_dir = arg[1]
local arch = arg[2]
local platform = arg[3]
local output_path = arg[4]
local libs = {}

for i = 5, #arg do
    table.insert(libs, arg[i])
end

if not kclib_dist_dir or not arch or not platform or not output_path or #libs == 0 then
    io.stderr:write("Usage: lua gen_bridge_api.lua <kclib_dist_dir> <arch> <platform> <output_path> <lib1> [lib2...]\n")
    os.exit(1)
end

generate_bridge_api(libs, kclib_dist_dir, arch, platform, output_path)