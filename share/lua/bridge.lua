-- bridge.lua
-- Summary: Projects kcapp Lua bindings through the wvw JavaScript transport.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: https://www.gnu.org/licenses/gpl-3.0.html

local ffi = require("ffi")
local kcapp = require("kcapp")
local bridge = {}

local KC_WVW_OK = 0
local KC_WVW_ERROR = -1
local states = {}

local json = {}

local function utf8_char(codepoint)
    if codepoint <= 0x7f then return string.char(codepoint) end
    if codepoint <= 0x7ff then
        return string.char(0xc0 + math.floor(codepoint / 0x40),
            0x80 + codepoint % 0x40)
    end
    return string.char(0xe0 + math.floor(codepoint / 0x1000),
        0x80 + math.floor(codepoint / 0x40) % 0x40,
        0x80 + codepoint % 0x40)
end

function json.encode(value)
    local kind = type(value)
    if kind == "nil" then
        return "null"
    end
    if kind == "boolean" then
        return value and "true" or "false"
    end
    if kind == "number" then
        return string.format("%.14g", value)
    end
    if kind == "string" then
        return '"' .. value:gsub('[\\"\b\f\n\r\t]', {
            ['\\'] = '\\\\',
            ['"'] = '\\"',
            ['\b'] = '\\b',
            ['\f'] = '\\f',
            ['\n'] = '\\n',
            ['\r'] = '\\r',
            ['\t'] = '\\t'
        }) .. '"'
    end
    if kind == "table" then
        local array = true
        local maximum = 0
        for key in pairs(value) do
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
                array = false
                break
            end
            if key > maximum then maximum = key end
        end
        local parts = {}
        if array then
            for index = 1, maximum do
                parts[#parts + 1] = json.encode(value[index])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for key, item in pairs(value) do
            if type(key) == "string" then
                parts[#parts + 1] = json.encode(key) .. ":" .. json.encode(item)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("unsupported JSON value type: " .. kind)
end

function json.decode(source)
    local position = 1
    local length = #source
    local parse_value
    local parse_object
    local parse_array
    local parse_string
    local parse_number

    local function skip_space()
        while position <= length and source:sub(position, position):match("%s") do
            position = position + 1
        end
    end

    parse_string = function()
        position = position + 1
        local parts = {}
        while position <= length do
            local char = source:sub(position, position)
            if char == '"' then
                position = position + 1
                return table.concat(parts)
            end
            if char == "\\" then
                position = position + 1
                local escape = source:sub(position, position)
                if escape == "u" then
                    local hex = source:sub(position + 1, position + 4)
                    parts[#parts + 1] = utf8_char(tonumber(hex, 16))
                    position = position + 5
                else
                    local escapes = {
                        ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
                        b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'
                    }
                    parts[#parts + 1] = escapes[escape] or escape
                    position = position + 1
                end
            else
                parts[#parts + 1] = char
                position = position + 1
            end
        end
        error("unterminated JSON string")
    end

    parse_number = function()
        local start = position
        while position <= length and source:sub(position, position):match("[-+0-9.eE]") do
            position = position + 1
        end
        return tonumber(source:sub(start, position - 1))
    end

    parse_array = function()
        position = position + 1
        local result = {}
        skip_space()
        if source:sub(position, position) == "]" then
            position = position + 1
            return result
        end
        while true do
            result[#result + 1] = parse_value()
            skip_space()
            local char = source:sub(position, position)
            if char == "]" then
                position = position + 1
                return result
            end
            if char ~= "," then error("invalid JSON array") end
            position = position + 1
        end
    end

    parse_object = function()
        position = position + 1
        local result = {}
        skip_space()
        if source:sub(position, position) == "}" then
            position = position + 1
            return result
        end
        while true do
            skip_space()
            local key = parse_string()
            skip_space()
            if source:sub(position, position) ~= ":" then
                error("invalid JSON object")
            end
            position = position + 1
            result[key] = parse_value()
            skip_space()
            local char = source:sub(position, position)
            if char == "}" then
                position = position + 1
                return result
            end
            if char ~= "," then error("invalid JSON object") end
            position = position + 1
        end
    end

    parse_value = function()
        skip_space()
        local char = source:sub(position, position)
        if char == '"' then return parse_string() end
        if char == "{" then return parse_object() end
        if char == "[" then return parse_array() end
        if source:sub(position, position + 3) == "true" then
            position = position + 4
            return true
        end
        if source:sub(position, position + 4) == "false" then
            position = position + 5
            return false
        end
        if source:sub(position, position + 3) == "null" then
            position = position + 4
            return nil
        end
        return parse_number()
    end

    return parse_value()
end

local function result(state, out, value)
    local buffer = ffi.new("char[?]", #value + 1)
    ffi.copy(buffer, value, #value)
    buffer[#value] = 0
    state.response = buffer
    out[0] = ffi.cast("const char *", buffer)
end

local function failure(state, out, code, message)
    result(state, out, json.encode({code = code, message = message}))
    return KC_WVW_ERROR
end

local function dispatch(ctx, method, params_json, out, userdata)
    local state = states[tostring(ctx)]
    if not state then
        return KC_WVW_ERROR
    end

    local method_name = method ~= nil and method ~= ffi.NULL and ffi.string(method) or ""
    if method_name ~= "kcapp_bridge" then
        return failure(state, out, "METHOD_NOT_FOUND", "Bridge method not available")
    end

    local source = params_json ~= nil and params_json ~= ffi.NULL and ffi.string(params_json) or "{}"
    local ok, request = pcall(json.decode, source)
    if not ok or type(request) ~= "table" then
        return failure(state, out, "INVALID_PARAMS", "Invalid bridge request")
    end

    local module = state.modules[request.lib]
    local allowed = state.methods[request.lib]
    if not module or not allowed or not allowed[request.fn] then
        return failure(state, out, "METHOD_NOT_FOUND", "Bridge operation not available")
    end

    local operation = module[request.fn]
    local args = request.args or {}
    local call_ok, value = pcall(operation, unpack(args))
    if not call_ok then
        return failure(state, out, "EXEC_ERROR", tostring(value))
    end

    local encode_ok, encoded = pcall(json.encode, value)
    if not encode_ok then
        return failure(state, out, "EXEC_ERROR", "Bridge result is not JSON-compatible")
    end

    result(state, out, encoded)
    return KC_WVW_OK
end

local function facade(libraries)
    local lines = {
        "(function(){",
        "if(!window.NativeBridge||!window.NativeBridge.kcapp_bridge){return;}",
        "var send=window.NativeBridge.kcapp_bridge;",
        "function call(lib,fn,args){return send({lib:lib,fn:fn,args:Array.prototype.slice.call(args)});}"
    }

    for _, library in ipairs(libraries) do
        lines[#lines + 1] = "window.NativeBridge[" .. json.encode(library.name) .. "]={};"
        for _, method in ipairs(library.methods) do
            lines[#lines + 1] =
                "window.NativeBridge[" .. json.encode(library.name) .. "][" ..
                json.encode(method) .. "]=function(){return call(" ..
                json.encode(library.name) .. "," .. json.encode(method) ..
                ",arguments);};"
        end
    end
    lines[#lines + 1] = "})();"
    return table.concat(lines)
end

-- Install automatic kclib projection on one WebView.
-- @param window table kcapp window object
-- @param libraries table array of kclib names
-- @return boolean true on success
function bridge.install(window, libraries)
    if type(window) ~= "table" or not window._wvw_ctx then
        error("kcapp.bridge: invalid window", 2)
    end
    if type(libraries) ~= "table" then
        error("kcapp.bridge: libraries must be a table", 2)
    end

    local state = {
        modules = {},
        methods = {}
    }
    local exposed = {}

    for _, name in ipairs(libraries) do
        local module = kcapp.load(name)
        local description = kcapp._description(name)
        local methods = {}
        local allowed = {}
        for operation, info in pairs(description.functions) do
            if info.bridgeable then
                methods[#methods + 1] = operation
                allowed[operation] = true
            end
        end
        table.sort(methods)
        state.modules[name] = module
        state.methods[name] = allowed
        exposed[#exposed + 1] = {name = name, methods = methods}
    end
    table.sort(exposed, function(a, b) return a.name < b.name end)

    local names = ffi.new("const char *[1]")
    names[0] = "kcapp_bridge"
    local options = ffi.new("kc_wvw_bridge_options_t")
    options.methods = names
    options.method_count = 1
    options.allow_file = 1
    options.allow_data = 0
    options.allow_localhost = 0

    state.callback = ffi.cast("kc_wvw_bridge_callback_t", dispatch)
    state.names = names
    options.callback = state.callback
    states[tostring(window._wvw_ctx)] = state

    local wvw = kcapp._raw("wvw")
    if wvw.kc_wvw_enable_bridge(window._wvw_ctx, options) ~= KC_WVW_OK then
        states[tostring(window._wvw_ctx)] = nil
        state.callback:free()
        error("kcapp.bridge: failed to enable WebView bridge", 2)
    end

    if wvw.kc_wvw_add_init_script(window._wvw_ctx, facade(exposed)) ~= KC_WVW_OK then
        states[tostring(window._wvw_ctx)] = nil
        state.callback:free()
        error("kcapp.bridge: failed to install JavaScript facade", 2)
    end

    return true
end

-- Release bridge-owned callback state for one window.
-- @param window table kcapp window object
-- @return nil
function bridge.release(window)
    if type(window) ~= "table" or not window._wvw_ctx then
        return
    end
    local key = tostring(window._wvw_ctx)
    local state = states[key]
    if not state then
        return
    end
    states[key] = nil
    if state.callback then
        state.callback:free()
        state.callback = nil
    end
end

return bridge
