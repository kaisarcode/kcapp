-- bridge.lua
-- Summary: Transports explicit Lua methods through the wvw JavaScript bridge.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: https://www.gnu.org/licenses/gpl-3.0.html

local ffi = require("ffi")
local kcapp = require("kcapp")
local bridge = {}

local KC_WVW_OK = 0
local KC_WVW_ERROR = -1

local wvw_lib = nil
local bridge_states = {}

local json = {}

-- Encode a codepoint as UTF-8 character.
-- @param codepoint integer Unicode codepoint
-- @return string UTF-8 encoded character
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

-- Load the wvw library once for bridge installation.
-- @return cdata loaded wvw library
local function load_wvw()
    if wvw_lib then
        return wvw_lib
    end
    wvw_lib = kcapp.load("wvw")
    return wvw_lib
end

-- Store one JSON response in state-owned memory.
-- @param state table bridge state
-- @param result_json_ptr cdata output pointer
-- @param value string serialized JSON value
-- @return boolean success
local function bridge_result(state, result_json_ptr, value)
    local buffer = ffi.new("char[?]", #value + 1)
    ffi.copy(buffer, value, #value)
    buffer[#value] = 0
    state.response = buffer
    result_json_ptr[0] = buffer
    return true
end

-- Return one serialized bridge error.
-- @param state table bridge state
-- @param result_json_ptr cdata output pointer
-- @param code string stable error code
-- @param message string error message
-- @return integer KC_WVW_ERROR
local function bridge_error(state, result_json_ptr, code, message)
    bridge_result(state, result_json_ptr, json.encode({
        code = code,
        message = message
    }))
    return KC_WVW_ERROR
end

-- Dispatch one explicit application bridge method.
-- @param ctx cdata WebView context
-- @param method cdata method name
-- @param params_json cdata serialized JSON parameters
-- @param result_json_ptr cdata output response pointer
-- @param userdata cdata unused user data
-- @return integer KC_WVW_OK or KC_WVW_ERROR
local function bridge_dispatch(ctx, method, params_json, result_json_ptr, userdata)
    local state = bridge_states[tostring(ctx)]
    if not state then
        return KC_WVW_ERROR
    end

    local method_name = ""
    if method ~= nil and method ~= ffi.NULL then
        method_name = ffi.string(method)
    end

    local handler = state.methods[method_name]
    if not handler then
        return bridge_error(
            state,
            result_json_ptr,
            "METHOD_NOT_FOUND",
            "Bridge method not available: " .. method_name
        )
    end

    local params_text = "null"
    if params_json ~= nil and params_json ~= ffi.NULL then
        params_text = ffi.string(params_json)
    end

    local ok, params = pcall(json.decode, params_text)
    if not ok then
        return bridge_error(
            state,
            result_json_ptr,
            "INVALID_PARAMS",
            "Invalid JSON parameters"
        )
    end

    local call_ok, result = pcall(handler, params)
    if not call_ok then
        return bridge_error(
            state,
            result_json_ptr,
            "EXEC_ERROR",
            tostring(result)
        )
    end

    local encode_ok, result_json = pcall(json.encode, result)
    if not encode_ok then
        return bridge_error(
            state,
            result_json_ptr,
            "EXEC_ERROR",
            "Bridge result is not JSON-compatible"
        )
    end

    bridge_result(state, result_json_ptr, result_json)
    return KC_WVW_OK
end

-- Install explicit application methods on one WebView instance.
-- @param window table kcapp window wrapper
-- @param methods table method-name to Lua-function map
-- @param loaded_wvw optional loaded wvw library
-- @return boolean true on success
function bridge.install(window, methods, loaded_wvw)
    if type(window) ~= "table" or not window._wvw_ctx then
        error("kcapp.bridge: window missing _wvw_ctx", 2)
    end
    if type(methods) ~= "table" then
        error("kcapp.bridge: methods must be a table", 2)
    end

    local names = {}
    for name, handler in pairs(methods) do
        if type(name) ~= "string" or name == "" then
            error("kcapp.bridge: method names must be non-empty strings", 2)
        end
        if type(handler) ~= "function" then
            error("kcapp.bridge: method '" .. name .. "' must be a function", 2)
        end
        names[#names + 1] = name
    end
    table.sort(names)

    if #names == 0 then
        error("kcapp.bridge: at least one method is required", 2)
    end

    local wvw = loaded_wvw or load_wvw()
    local ctx = window._wvw_ctx
    local state = {
        methods = methods,
        names = names
    }

    local method_list = ffi.new("const char *[?]", #names)
    for index, name in ipairs(names) do
        method_list[index - 1] = name
    end

    local options = ffi.new("kc_wvw_bridge_options_t")
    options.methods = method_list
    options.method_count = #names
    options.allow_file = 1
    options.allow_data = 0
    options.allow_localhost = 0

    state.callback = ffi.cast("kc_wvw_bridge_callback_t", bridge_dispatch)
    options.callback = state.callback
    options.userdata = nil
    bridge_states[tostring(ctx)] = state

    local ret = wvw.kc_wvw_enable_bridge(ctx, options)
    if ret ~= KC_WVW_OK then
        bridge_states[tostring(ctx)] = nil
        state.callback:free()
        local err = wvw.kc_wvw_get_error(ctx)
        local message = (err ~= nil and err ~= ffi.NULL)
            and ffi.string(err)
            or "unknown error"
        error("kcapp.bridge: failed to enable wvw bridge: " .. message, 2)
    end

    return true
end

return bridge
