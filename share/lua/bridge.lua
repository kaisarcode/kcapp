if arg[1] == "--materialize" then
    local function read_file(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end
    local function write_file(path, content)
        local file = assert(io.open(path, "wb"))
        file:write(content)
        file:close()
    end

    local function parse_cdef(content)
        local lines = {}
        for line in content:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end

        local declarations = {}
        local current = ""
        local paren_depth = 0
        for _, line in ipairs(lines) do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed == "" or trimmed:match("^//") or trimmed:match("^#") then
                goto continue
            end
            current = current .. " " .. trimmed
            for i = 1, #trimmed do
                local c = trimmed:sub(i, i)
                if c == "(" then paren_depth = paren_depth + 1 end
                if c == ")" then paren_depth = paren_depth - 1 end
            end
            if paren_depth == 0 and current:match("[;{}]%s*$") then
                local decl = current:match("^%s*(.-)%s*$")
                if decl ~= "" then
                    table.insert(declarations, decl)
                end
                current = ""
            end
            ::continue::
        end

        local functions = {}
        for _, decl in ipairs(declarations) do
            if decl:match("^enum") or decl:match("^typedef") then
                goto continue
            end
            local name_start, name_end = decl:find("[%a_][%w_]*[%s%*]*%s*%(")
            if name_start then
                local name = decl:sub(name_start, name_end - 1)
                local ret_type = decl:sub(1, name_start - 1):match("^%s*(.-)%s*$")
                local params_str = decl:match("%((.*)%)")
                local params = {}
                if params_str and params_str ~= "void" and params_str ~= "" then
                    for param in params_str:gmatch("[^,]+") do
                        param = param:match("^%s*(.-)%s*$")
                        if param ~= "" then
                            table.insert(params, "{ type = " .. string.format("%q", param) .. " }")
                        end
                    end
                end
                table.insert(functions, string.format("        { name = %q, ret_type = %q, params = {%s} }", name, ret_type, table.concat(params, ", ")))
            end
            ::continue::
        end
        return functions
    end

    local dist, arch, platform, output = arg[2], arg[3], arg[4], arg[5]
    local libraries = {}
    for index = 6, #arg do libraries[#libraries + 1] = arg[index] end
    table.sort(libraries)
    local metadata = {}
    for _, library in ipairs(libraries) do
        local directory = dist .. "/" .. library .. ".c/" .. arch .. "/" .. platform
        local cdef_path = directory .. "/lib" .. library .. ".cdef"
        local shared_lib = directory .. "/lib" .. library .. ".so"
        if platform == "macos" then
            shared_lib = directory .. "/lib" .. library .. ".dylib"
        elseif platform == "windows" then
            shared_lib = directory .. "/lib" .. library .. ".dll"
        end
        local cdef_file = io.open(cdef_path, "rb")
        if not cdef_file then error("kcapp bridge: missing cdef for " .. library .. ": " .. cdef_path) end
        local cdef_content = cdef_file:read("*a")
        cdef_file:close()
        local f = io.open(shared_lib, "rb")
        if not f then error("kcapp bridge: missing shared library for " .. library .. ": " .. shared_lib) end
        f:close()
        local functions = parse_cdef(cdef_content)
        if #functions == 0 then error("kcapp bridge: no public API discovered for " .. library) end
        table.sort(functions)
        metadata[#metadata + 1] = "    [" .. string.format("%q", library) .. "] = { functions = {\n" .. table.concat(functions, ",\n") .. "\n    } },"
    end
    local source = read_file(arg[0])
    source = source:gsub("^.-\nend\n\n", "", 1)
    source = source:gsub("        %-%- @BRIDGE_API_LIBRARIES@", table.concat(metadata, "\n"), 1)
    write_file(output, source)
    os.exit(0)
end

-- bridge.lua
-- Summary: kcapp bridge template with embedded API metadata placeholder.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local ffi = require("ffi")
local kcapp = require("kcapp")
local bridge = {}

ffi.cdef[[void *malloc(size_t size);]]

-- Opaque pointer handle registry
local handle_registry = {}
local handle_counter = 0

local function handle_register(ptr)
    if ptr == nil or ptr == ffi.NULL then
        return nil
    end
    handle_counter = handle_counter + 1
    local id = handle_counter
    handle_registry[id] = ptr
    return {__kcapp_handle = id}
end

local function handle_unwrap(obj)
    if type(obj) == "table" and obj.__kcapp_handle then
        local id = obj.__kcapp_handle
        local ptr = handle_registry[id]
        if ptr == nil then
            error("kcapp.bridge: invalid handle " .. id)
        end
        return ptr
    end
    return obj
end

local KC_WVW_OK = 0
local KC_WVW_ERROR = -1

local wvw_lib = nil
local bridge_states = {}

-- ============================================================================
-- EMBEDDED BRIDGE API METADATA (populated at build time)
-- ============================================================================

local bridge_api = {
    version = 1,
    libraries = {
        -- @BRIDGE_API_LIBRARIES@
    }
}

-- ============================================================================
-- SIMPLE JSON ENCODER/DECODER (subset for bridge use)
-- ============================================================================

local json = {}

local function utf8_char(codepoint)
    if codepoint <= 0x7f then return string.char(codepoint) end
    if codepoint <= 0x7ff then return string.char(0xc0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40) end
    return string.char(0xe0 + math.floor(codepoint / 0x1000), 0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
end

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
    
    local parse_value, parse_object, parse_array, parse_string, parse_number, parse_literal
    
    local function skip_ws()
        while pos <= len and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end
    
    parse_value = function()
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
    
    parse_literal = function(lit, val)
        if str:sub(pos, pos + #lit - 1) == lit then
            pos = pos + #lit
            return val
        end
        error("Invalid literal at position " .. pos)
    end
    
    parse_number = function()
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
    
    parse_string = function()
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
                    table.insert(result, utf8_char(tonumber(hex, 16)))
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
    
    parse_array = function()
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
    
    parse_object = function()
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
    local ok, lib = pcall(kcapp.load, "wvw")
    if not ok then
        for _, mod in pairs(package.loaded) do
            if type(mod) == "table" and mod.kc_wvw_open then
                return mod
            end
        end
        error("kcapp.bridge: wvw not loaded")
    end
    wvw_lib = lib
    return wvw_lib
end

-- Opaque pointer handle registry
local handle_registry = {}
local handle_counter = 0

local function handle_register(ptr)
    if ptr == nil or ptr == ffi.NULL then
        return nil
    end
    handle_counter = handle_counter + 1
    local id = handle_counter
    handle_registry[id] = ptr
    return {__kcapp_handle = id}
end

local function handle_unwrap(obj)
    if type(obj) == "table" and obj.__kcapp_handle then
        local id = obj.__kcapp_handle
        local ptr = handle_registry[id]
        if ptr == nil then
            error("kcapp.bridge: invalid handle " .. id)
        end
        return ptr
    end
    return obj
end

local function ffi_type_to_ctype(ffi_type)
    if ffi_type == "void" then return "void" end
    -- Strip parameter name if present (e.g., "const char *id" -> "const char *")
    local base_type = ffi_type:match("^(.+%*)%s*[%w_]+$") or ffi_type:match("^(.+)%s+[%w_]+$") or ffi_type
    base_type = base_type:gsub("%s+$", "")
    -- Check for output buffer pattern (char *err, char *buf, etc.)
    if ffi_type:match("char%s*%*%s*[eE][rR][rR]") or ffi_type:match("char%s*%*%s*[bB][uU][fF]") then
        return "pointer"
    end
    if base_type == "const char *" or base_type == "char *" then return "string" end
    if base_type == "const void *" or base_type == "void *" then return "pointer" end
    if base_type == "size_t" or base_type == "uint64_t" or base_type == "int" or base_type == "unsigned int" then return "number" end
    if base_type:match("%*%s*$") then return "pointer" end
    return "unknown"
end

local function convert_js_args_to_ffi(func_info, js_args)
    local ffi_args = {}
    local js_index = 1
    
    for i, param in ipairs(func_info.params) do
        local js_val = js_args[js_index]
        local ctype = ffi_type_to_ctype(param.type)
        
        -- Handle case where JS omits output buffer params (e.g., redp2p_set_vip skips err buffer)
        -- If JS arg is number but C param is char* pointer, insert buffer and don't consume JS arg
        if js_val ~= nil and type(js_val) == "number" and ctype == "pointer" and param.type:match("char%s*%*") then
            -- JS passed a number (err_cap) but C expects char* (err buffer)
            -- Insert the buffer and process this param again with same JS arg
            local err_buf = ffi.new("char[256]")
            table.insert(ffi_args, err_buf)
        else
            -- Normal case: consume JS arg
            js_val = js_args[js_index]
            js_index = js_index + 1
            
            -- Now insert the value
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
                -- Try to unwrap handle object
                local unwrapped = handle_unwrap(js_val)
                if unwrapped ~= js_val then
                    -- It was a handle object, use the unwrapped pointer
                    table.insert(ffi_args, unwrapped)
                elseif type(js_val) == "string" then
                    local buf = ffi.new("char[?]", #js_val + 1)
                    ffi.copy(buf, js_val)
                    table.insert(ffi_args, buf)
                elseif type(js_val) == "cdata" then
                    table.insert(ffi_args, js_val)
                else
                    error("kcapp.bridge: argument " .. i .. " must be string, handle, or buffer for " .. func_info.name, 2)
                end
            else
                error("kcapp.bridge: unsupported parameter type " .. param.type .. " for " .. func_info.name, 2)
            end
        end
    end
    return ffi_args
end

local function convert_ffi_result_to_js(func_info, result)
    local ret_type = func_info.ret_type
    
    -- Check if this is an output pattern function (returns handle via **out param)
    local params = func_info.params
    local is_output_pattern = (ret_type == "int" or ret_type == "size_t" or ret_type == "uint64_t") 
        and #params == 1 
        and params[1].type:match("%*%*")  -- contains **
    
    if ret_type == "void" then
        return nil
    elseif ret_type == "const char *" or ret_type == "char *" then
        if result == nil then return nil end
        return ffi.string(result)
    elseif ret_type == "void *" or ret_type == "const void *" then
        if result == nil then return nil end
        return handle_register(result)
    elseif ret_type == "uint64_t" or ret_type == "size_t" or ret_type == "int" or ret_type == "unsigned int" then
        -- Output pattern functions return pointer via **out param despite int ret_type
        if is_output_pattern and type(result) == "cdata" then
            return handle_register(result)
        end
        -- Scalar integer types: always convert to number, never wrap as handle
        return tonumber(result)
    elseif ret_type:match("%*%s*$") then
        if result == nil then return nil end
        return handle_register(result)
    else
        return tostring(result)
    end
end

local function bridge_result(result_json_ptr, value)
    local buffer = ffi.C.malloc(#value + 1)
    if buffer == nil then return false end
    ffi.copy(buffer, value, #value)
    ffi.cast("char *", buffer)[#value] = 0
    ffi.cast("char **", result_json_ptr)[0] = ffi.cast("char *", buffer)
    return true
end

local function bridge_dispatch(ctx, method, params_json, result_json_ptr, userdata)
    local method_str = "UNKNOWN"
    if method ~= nil and method ~= ffi.NULL then
        local ptr = ffi.cast("const char*", method)
        local bytes = {}
        for i = 0, 99 do
            local c = ptr[i]
            if c == 0 then break end
            table.insert(bytes, string.char(c))
        end
        method_str = table.concat(bytes)
    end
    local state = bridge_states[tostring(ctx)]
    if method_str ~= "kcapp_bridge" or not state then
        bridge_result(result_json_ptr, json_encode({code = "METHOD_NOT_FOUND", message = "Bridge method not available"}))
        return KC_WVW_ERROR
    end
    local params_json_str = ffi.string(params_json)
    local ok, params = pcall(json_decode, params_json_str)
    if not ok then
        local err = json_encode({code = "INVALID_PARAMS", message = "Invalid JSON params"})
        bridge_result(result_json_ptr, err)
        return KC_WVW_ERROR
    end

    local lib_name = params.lib
    local fn_name = params.fn
    local args = params.args or {}

    local lib_info = bridge_api.libraries[lib_name]
    if not lib_info or not state.libraries[lib_name] then
        local err = json_encode({code = "LIB_NOT_FOUND", message = "Library not exposed: " .. lib_name})
        bridge_result(result_json_ptr, err)
        return KC_WVW_ERROR
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
        bridge_result(result_json_ptr, err)
        return KC_WVW_ERROR
    end

    local function call_with_output_handling(lib, func_info, args)
        -- Check if function has output parameter pattern: returns int, has single **out param
        local ret_type = func_info.ret_type
        local params = func_info.params
        
        local is_output_pattern = (ret_type == "int" or ret_type == "size_t" or ret_type == "uint64_t") 
            and #params == 1 
            and params[1].type:match("%*%*")  -- contains **
        
        if is_output_pattern then
            -- Allocate output buffer - need to handle type like "redp2p_t **out"
            local base_type = params[1].type:gsub("%s*%*%s*[%w_]+$", "")  -- remove param name and one *
            base_type = base_type:gsub("%s+", "")  -- remove spaces
            base_type = base_type:gsub("%*+$", "")  -- remove trailing *
            local out_buf = ffi.new(base_type .. "*[1]")
            local ret = lib[func_info.name](out_buf)
            if ret == 0 then
                return out_buf[0]
            else
                return nil, ret  -- return nil and error code
            end
        else
            -- Normal call
            local ffi_args = convert_js_args_to_ffi(func_info, args)
            return lib[func_info.name](unpack(ffi_args))
        end
    end

    local ret_type = func_info.ret_type
    local params = func_info.params
    local is_output_pattern = (ret_type == "int" or ret_type == "size_t" or ret_type == "uint64_t") 
        and #params == 1 
        and params[1].type:match("%*%*")  -- contains **

    local lib = kcapp.load(lib_name)

    local ok, result = pcall(call_with_output_handling, lib, func_info, args)

    if not ok then
        local err = json_encode({code = "EXEC_ERROR", message = "FFI call failed: " .. tostring(result)})
        bridge_result(result_json_ptr, err)
        return KC_WVW_ERROR
    end

    local js_result = convert_ffi_result_to_js(func_info, result)
    local result_json = json_encode(js_result)
    if not bridge_result(result_json_ptr, result_json) then return KC_WVW_ERROR end
    return KC_WVW_OK
end

function bridge.install(window, libs, wvw_lib)
    local wvw = wvw_lib or load_wvw()

    -- Validate requested libraries exist in embedded metadata
    for _, lib_name in ipairs(libs) do
        if not bridge_api.libraries[lib_name] then
            error("kcapp.bridge: library not available in bridge: " .. lib_name, 2)
        end
    end

    local state = {libraries = {}}
    local bridge_methods = {"kcapp_bridge"}
    local bridge_opts = ffi.new("kc_wvw_bridge_options_t")
    bridge_opts.methods = ffi.new("const char*[?]", #bridge_methods)
    for i, m in ipairs(bridge_methods) do
        bridge_opts.methods[i-1] = m
    end
    bridge_opts.method_count = #bridge_methods
    bridge_opts.allow_file = 1
    bridge_opts.allow_data = 0
    bridge_opts.allow_localhost = 0

    for _, lib_name in ipairs(libs) do state.libraries[lib_name] = true end
    state.callback = ffi.cast("kc_wvw_bridge_callback_t", bridge_dispatch)
    bridge_opts.callback = state.callback
    bridge_opts.userdata = nil

    local wvw_ctx = window._wvw_ctx
    if not wvw_ctx then
        error("kcapp.bridge: window missing _wvw_ctx", 2)
    end

    bridge_states[tostring(wvw_ctx)] = state

    local ret = wvw.kc_wvw_enable_bridge(wvw_ctx, bridge_opts)
    if ret ~= 0 then
        local err = wvw.kc_wvw_get_error(wvw_ctx)
        local err_str = (err ~= nil and err ~= ffi.NULL) and ffi.string(err) or "unknown error"
        error("kcapp.bridge: failed to enable wvw bridge: " .. err_str, 2)
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
    if wvw.kc_wvw_add_init_script(wvw_ctx, js_code) ~= 0 then
        bridge_states[tostring(wvw_ctx)] = nil
        error("kcapp.bridge: failed to install JavaScript facade", 2)
    end
end

function bridge.generate_js_facade(lib_map)
    local parts = {}
    table.insert(parts, "(function(){")
    table.insert(parts, "if(!window.NativeBridge){window.NativeBridge={};}")
    table.insert(parts, "window.NativeBridge._kcappBridgeSend=function(lib,fn,args){")
    table.insert(parts, "return new Promise(function(resolve,reject){")
    table.insert(parts, "window.NativeBridge.kcapp_bridge({lib:lib,fn:fn,args:args}).then(resolve).catch(reject);")
    table.insert(parts, "});};")

    local lib_names = {}
    for lib_name in pairs(lib_map) do
        table.insert(lib_names, lib_name)
    end
    table.sort(lib_names)

    for _, lib_name in ipairs(lib_names) do
        local funcs = lib_map[lib_name]
        local sorted_funcs = {}
        for _, fn in ipairs(funcs) do
            table.insert(sorted_funcs, fn)
        end
        table.sort(sorted_funcs)
        table.insert(parts, "window.NativeBridge." .. lib_name .. "={};")
        for _, fn in ipairs(sorted_funcs) do
            table.insert(parts, "window.NativeBridge." .. lib_name .. "." .. fn .. "=function(...args){")
            table.insert(parts, "return window.NativeBridge._kcappBridgeSend('" .. lib_name .. "','" .. fn .. "',args);")
            table.insert(parts, "};")
        end
    end
    table.insert(parts, "})();")
    return table.concat(parts, "\n")
end

return bridge