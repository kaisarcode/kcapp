-- bridge.lua
-- Summary: kcapp bridge template with embedded API metadata placeholder.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local ffi = require("ffi")
local kcapp = require("kcapp")
local bridge = {}

local wvw_lib = nil
local bridge_callback_ref = nil

-- ============================================================================
-- EMBEDDED BRIDGE API METADATA (populated at build time)
-- ============================================================================

local bridge_api = {
    version = 1,
    libraries = {
        @BRIDGE_API_LIBRARIES@
    }
}

-- ============================================================================
-- SIMPLE JSON ENCODER/DECODER (subset for bridge use)
-- ============================================================================

local json = {}

function json.encode(val)
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val or val == math.huge or val == -math.huge then
            return "null"
        end
        return string.format("%.14g", val)
    elseif t == "string" then
        return '"' .. val:gsub('[\\"\b\f\n\r\t]', {
            ['\\'] = '\\\\', ['"'] = '\\"', ['\b'] = '\\b',
            ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'
        }) .. '"'
    elseif t == "table" then
        local is_array = true
        local max_index = 0
        for k, v in pairs(val) do
            if type(k) ~= "number" or k <= 0 or k % 1 ~= 0 then
                is_array = false
                break
            end
            if k > max_index then max_index = k end
        end
        if is_array and max_index > 0 and max_index == #val then
            local parts = {}
            for i = 1, max_index do
                parts[i] = json.encode(val[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                if type(k) == "string" then
                    table.insert(parts, json.encode(k) .. ":" .. json.encode(v))
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

function json.decode(str)
    local pos = 1
    local len = #str
    
    local function skip_ws()
        while pos <= len and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end
    
    local function parse_value()
        skip_ws()
        if pos > len then return nil end
        local c = str:sub(pos, pos)
        if c == "{" then return parse_object() end
        if c == "[" then return parse_array() end
        if c == '"' then return parse_string() end
        if c == "t" then return parse_literal("true", true) end
        if c == "f" then return parse_literal("false", false) end
        if c == "n" then return parse_literal("null", nil) end
        return parse_number()
    end
    
    local function parse_literal(lit, val)
        if str:sub(pos, pos + #lit - 1) == lit then
            pos = pos + #lit
            return val
        end
        error("Invalid literal at position " .. pos)
    end
    
    local function parse_number()
        local start = pos
        if str:sub(pos, pos) == "-" then pos = pos + 1 end
        while pos <= len and str:sub(pos, pos):match("%d") do pos = pos + 1 end
        if str:sub(pos, pos) == "." then
            pos = pos + 1
            while pos <= len and str:sub(pos, pos):match("%d") do pos = pos + 1 end
        end
        if str:sub(pos, pos):match("[eE]") then
            pos = pos + 1
            if str:sub(pos, pos):match("[+-]") then pos = pos + 1 end
            while pos <= len and str:sub(pos, pos):match("%d") do pos = pos + 1 end
        end
        return tonumber(str:sub(start, pos - 1))
    end
    
    local function parse_string()
        pos = pos + 1 -- skip opening quote
        local result = {}
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return table.concat(result)
            elseif c == "\\" then
                pos = pos + 1
                if pos > len then error("Unterminated escape") end
                local esc = str:sub(pos, pos)
                if esc == "u" then
                    pos = pos + 1
                    local hex = str:sub(pos, pos + 3)
                    pos = pos + 4
                    table.insert(result, utf8.char(tonumber(hex, 16)))
                else
                    local escapes = {['"'] = '"', ['\\'] = '\\', ['/'] = '/', ['b'] = '\b', ['f'] = '\f', ['n'] = '\n', ['r'] = '\r', ['t'] = '\t'}
                    table.insert(result, escapes[esc] or esc)
                    pos = pos + 1
                end
            else
                table.insert(result, c)
                pos = pos + 1
            end
        end
        error("Unterminated string")
    end
    
    local function parse_array()
        pos = pos + 1 -- skip '['
        local result = {}
        skip_ws()
        if str:sub(pos, pos) == "]" then
            pos = pos + 1
            return result
        end
        while true do
            table.insert(result, parse_value())
            skip_ws()
            if str:sub(pos, pos) == "]" then
                pos = pos + 1
                return result
            end
            if str:sub(pos, pos) ~= "," then error("Expected ',' or ']' at position " .. pos) end
            pos = pos + 1
        end
    end
    
    local function parse_object()
        pos = pos + 1 -- skip '{'
        local result = {}
        skip_ws()
        if str:sub(pos, pos) == "}" then
            pos = pos + 1
            return result
        end
        while true do
            skip_ws()
            local key = parse_string()
            skip_ws()
            if str:sub(pos, pos) ~= ":" then error("Expected ':' at position " .. pos) end
            pos = pos + 1
            result[key] = parse_value()
            skip_ws()
            if str:sub(pos, pos) == "}" then
                pos = pos + 1
                return result
            end
            if str:sub(pos, pos) ~= "," then error("Expected ',' or '}' at position " .. pos) end
            pos = pos + 1
        end
    end
    
    local result = parse_value()
    skip_ws()
    if pos <= len then error("Trailing garbage at position " .. pos) end
    return result
end

local function json_encode(val)
    return json.encode(val)
end

local function json_decode(str)
    return json.decode(str)
end

-- ============================================================================
-- BRIDGE RUNTIME
-- ============================================================================

local function load_wvw()
    if wvw_lib then return wvw_lib end
    wvw_lib = kcapp.load("wvw")
    return wvw_lib
end

local function ffi_type_to_ctype(ffi_type)
    if ffi_type == "void" then return "void" end
    if ffi_type == "const char *" or ffi_type == "char *" then return "string" end
    if ffi_type == "const void *" or ffi_type == "void *" then return "pointer" end
    if ffi_type == "size_t" or ffi_type == "uint64_t" or ffi_type == "int" or ffi_type == "unsigned int" then return "number" end
    if ffi_type:match("%*%s*$") then return "pointer" end
    return "unknown"
end

local function convert_js_args_to_ffi(func_info, js_args)
    local ffi_args = {}
    for i, param in ipairs(func_info.params) do
        local js_val = js_args[i]
        local ctype = ffi_type_to_ctype(param.type)
        
        if ctype == "string" then
            if type(js_val) ~= "string" then
                error("kcapp.bridge: argument " .. i .. " must be string for " .. func_info.name, 2)
            end
            table.insert(ffi_args, js_val)
        elseif ctype == "number" then
            if type(js_val) ~= "number" then
                error("kcapp.bridge: argument " .. i .. " must be number for " .. func_info.name, 2)
            end
            table.insert(ffi_args, js_val)
        elseif ctype == "pointer" then
            if type(js_val) == "string" then
                local buf = ffi.new("char[?]", #js_val + 1)
                ffi.copy(buf, js_val)
                table.insert(ffi_args, buf)
            elseif type(js_val) == "cdata" then
                table.insert(ffi_args, js_val)
            else
                error("kcapp.bridge: argument " .. i .. " must be string or buffer for " .. func_info.name, 2)
            end
        else
            error("kcapp.bridge: unsupported parameter type " .. param.type .. " for " .. func_info.name, 2)
        end
    end
    return ffi_args
end

local function convert_ffi_result_to_js(func_info, result)
    local ret_type = func_info.ret_type
    
    if ret_type == "void" then
        return nil
    elseif ret_type == "const char *" or ret_type == "char *" then
        if result == nil then return nil end
        return ffi.string(result)
    elseif ret_type == "void *" or ret_type == "const void *" then
        if result == nil then return nil end
        return "<pointer>"
    elseif ret_type == "uint64_t" or ret_type == "size_t" or ret_type == "int" or ret_type == "unsigned int" then
        return tonumber(result)
    elseif ret_type:match("%*%s*$") then
        if result == nil then return nil end
        return "<pointer>"
    else
        return tostring(result)
    end
end

local function bridge_dispatch(ctx, method, params_json, result_json_ptr, userdata)
    local ok, params = pcall(json_decode, params_json)
    if not ok then
        local err = json_encode({code = "INVALID_PARAMS", message = "Invalid JSON params"})
        local err_ptr = ffi.new("char[?]", #err + 1)
        ffi.copy(err_ptr, err)
        ffi.cast("char **", result_json_ptr)[0] = err_ptr
        return 0
    end

    local lib_name = params.lib
    local fn_name = params.fn
    local args = params.args or {}

    local lib_info = bridge_api.libraries[lib_name]
    if not lib_info then
        local err = json_encode({code = "LIB_NOT_FOUND", message = "Library not exposed: " .. lib_name})
        local err_ptr = ffi.new("char[?]", #err + 1)
        ffi.copy(err_ptr, err)
        ffi.cast("char **", result_json_ptr)[0] = err_ptr
        return 0
    end

    local func_info = nil
    for _, f in ipairs(lib_info.functions) do
        if f.name == fn_name then
            func_info = f
            break
        end
    end

    if not func_info then
        local err = json_encode({code = "FUNC_NOT_FOUND", message = "Function not found: " .. fn_name})
        local err_ptr = ffi.new("char[?]", #err + 1)
        ffi.copy(err_ptr, err)
        ffi.cast("char **", result_json_ptr)[0] = err_ptr
        return 0
    end

    local lib = kcapp.load(lib_name)
    local ffi_args = convert_js_args_to_ffi(func_info, args)
    
    local ok, result = pcall(function()
        return lib[fn_name](unpack(ffi_args))
    end)

    if not ok then
        local err = json_encode({code = "EXEC_ERROR", message = "FFI call failed: " .. tostring(result)})
        local err_ptr = ffi.new("char[?]", #err + 1)
        ffi.copy(err_ptr, err)
        ffi.cast("char **", result_json_ptr)[0] = err_ptr
        return 0
    end

    local js_result = convert_ffi_result_to_js(func_info, result)
    local result_json = json_encode(js_result)
    local result_ptr = ffi.new("char[?]", #result_json + 1)
    ffi.copy(result_ptr, result_json)
    ffi.cast("char **", result_json_ptr)[0] = result_ptr
    return 0
end

function bridge.install(window, libs)
    local wvw = load_wvw()

    -- Validate requested libraries exist in embedded metadata
    for _, lib_name in ipairs(libs) do
        if not bridge_api.libraries[lib_name] then
            error("kcapp.bridge: library not available in bridge: " .. lib_name, 2)
        end
    end

    local bridge_methods = {"kcapp_bridge"}
    local bridge_opts = ffi.new("kc_wvw_bridge_options_t")
    bridge_opts.methods = ffi.new("const char*[?]", #bridge_methods)
    for i, m in ipairs(bridge_methods) do
        bridge_opts.methods[i-1] = m
    end
    bridge_opts.method_count = #bridge_methods
    bridge_opts.allow_file = 0
    bridge_opts.allow_data = 0
    bridge_opts.allow_localhost = 0

    bridge_callback_ref = ffi.cast("kc_wvw_bridge_callback_t", bridge_dispatch)
    bridge_opts.callback = bridge_callback_ref
    bridge_opts.userdata = nil

    local wvw_ctx = window._wvw_ctx
    if not wvw_ctx then
        error("kcapp.bridge: window missing _wvw_ctx", 2)
    end

    local ret = wvw.kc_wvw_enable_bridge(wvw_ctx, bridge_opts)
    if ret ~= 0 then
        error("kcapp.bridge: failed to enable wvw bridge: " .. wvw.kc_wvw_get_error(wvw_ctx), 2)
    end

    local js_setup = {}
    for _, lib_name in ipairs(libs) do
        local lib_info = bridge_api.libraries[lib_name]
        local ns = {}
        for _, f in ipairs(lib_info.functions) do
            table.insert(ns, f.name)
        end
        js_setup[lib_name] = ns
    end

    local js_code = bridge.generate_js_facade(js_setup)
    wvw.kc_wvw_post_bridge_event(wvw_ctx, js_code)
end

function bridge.generate_js_facade(lib_map)
    local parts = {}
    table.insert(parts, "(function(){")
    table.insert(parts, "if(!window.NativeBridge){window.NativeBridge={};}")
    table.insert(parts, "window.NativeBridge._kcappBridgeSend=function(lib,fn,args){")
    table.insert(parts, "return new Promise(function(resolve,reject){")
    table.insert(parts, "window.NativeBridge.kcapp_bridge({lib:lib,fn:fn,args:args}).then(resolve).catch(reject);")
    table.insert(parts, "});};")

    for lib_name, funcs in pairs(lib_map) do
        table.insert(parts, "window.NativeBridge." .. lib_name .. "={};")
        for _, fn in ipairs(funcs) do
            table.insert(parts, "window.NativeBridge." .. lib_name .. "." .. fn .. "=function(...args){")
            table.insert(parts, "return window.NativeBridge._kcappBridgeSend('" .. lib_name .. "','" .. fn .. "',args);")
            table.insert(parts, "};")
        end
    end
    table.insert(parts, "})();")
    return table.concat(parts, "\n")
end

return bridge