-- bridge.lua
-- Summary: Projects kcapp scripting APIs through the wvw JavaScript transport.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

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
        return string.char(
            0xc0 + math.floor(codepoint / 0x40),
            0x80 + codepoint % 0x40
        )
    end
    return string.char(
        0xe0 + math.floor(codepoint / 0x1000),
        0x80 + math.floor(codepoint / 0x40) % 0x40,
        0x80 + codepoint % 0x40
    )
end

local function encode_string(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
        if char == '\\' then return '\\\\' end
        if char == '"' then return '\\"' end
        local byte = string.byte(char)
        if byte == 8 then return '\\b' end
        if byte == 9 then return '\\t' end
        if byte == 10 then return '\\n' end
        if byte == 12 then return '\\f' end
        if byte == 13 then return '\\r' end
        return string.format("\\u%04x", byte)
    end) .. '"'
end

function json.encode(value)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        end
        return string.format("%.14g", value)
    end
    if kind == "string" then return encode_string(value) end
    if kind ~= "table" then
        error("unsupported JSON value type: " .. kind)
    end

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
                        ['"'] = '"',
                        ['\\'] = '\\',
                        ['/'] = '/',
                        b = '\b',
                        f = '\f',
                        n = '\n',
                        r = '\r',
                        t = '\t'
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
        local number = tonumber(source:sub(start, position - 1))
        if number == nil then error("invalid JSON number") end
        return number
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
            if source:sub(position, position) ~= '"' then
                error("invalid JSON object key")
            end
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

    local value = parse_value()
    skip_space()
    if position <= length then error("trailing JSON data") end
    return value
end

local function result(state, output, value)
    local encoded = json.encode(value)
    local buffer = ffi.new("char[?]", #encoded + 1)
    ffi.copy(buffer, encoded, #encoded)
    buffer[#encoded] = 0
    state.response = buffer
    output[0] = ffi.cast("const char *", buffer)
end

local function failure(state, output, code, message, status)
    local value = {
        code = code,
        message = message
    }
    if status ~= nil then value.status = status end
    result(state, output, value)
    return KC_WVW_ERROR
end

local function byte_array_to_string(values)
    local parts = {}
    local chunk = {}
    for index, value in ipairs(values) do
        chunk[#chunk + 1] = string.char(value)
        if #chunk == 4096 then
            parts[#parts + 1] = table.concat(chunk)
            chunk = {}
        end
    end
    if #chunk > 0 then parts[#parts + 1] = table.concat(chunk) end
    return table.concat(parts)
end

local function transport_in(state, value)
    if type(value) ~= "table" then return value end

    if value.__kcapp_object then
        local object = state.objects[value.__kcapp_object]
        if not object then
            error("unknown kcapp object")
        end
        return object
    end

    if value.__kcapp_bytes then
        return byte_array_to_string(value.__kcapp_bytes)
    end

    local result_value = {}
    for key, item in pairs(value) do
        result_value[key] = transport_in(state, item)
    end
    return result_value
end

local function register_object(state, object)
    local existing = state.object_ids[object]
    if existing then return existing end
    state.object_counter = state.object_counter + 1
    local id = state.object_counter
    state.objects[id] = object
    state.object_ids[object] = id
    return id
end

local function callback_free_methods(value)
    local methods = {}
    for _, name in ipairs(kcapp._object_methods(value)) do
        local signature = kcapp._signature(value._lib, name, value._type)
        local callback = false
        for _, parameter in ipairs(signature or {}) do
            if parameter.kind == "callback" then
                callback = true
                break
            end
        end
        if not callback then methods[#methods + 1] = name end
    end
    return methods
end

local function string_to_byte_array(value)
    local bytes = {}
    for index = 1, #value do
        bytes[index] = string.byte(value, index)
    end
    return bytes
end

local function transport_out(state, value, result_kind)
    if result_kind == "binary" and type(value) == "string" then
        return {__kcapp_bytes = string_to_byte_array(value)}
    end

    if kcapp._is_object(value) then
        return {
            __kcapp_object = register_object(state, value),
            __kcapp_type = value._type,
            __kcapp_methods = callback_free_methods(value)
        }
    end

    if type(value) ~= "table" then return value end

    local result_value = {}
    for key, item in pairs(value) do
        result_value[key] = transport_out(state, item)
    end
    return result_value
end

local function call_operation(state, request)
    local args = {}
    for index, value in ipairs(request.args or {}) do
        args[index] = transport_in(state, value)
    end

    if request.object then
        local object = state.objects[request.object]
        if not object then
            error("unknown kcapp object")
        end
        local method = object[request.fn]
        if type(method) ~= "function" then
            error("object method not available: " .. tostring(request.fn))
        end
        local value, status = method(object, unpack(args))
        return value, status,
            kcapp._result_kind(object._lib, request.fn, object._type)
    end

    local module = state.modules[request.lib]
    local allowed = state.methods[request.lib]
    if not module or not allowed or not allowed[request.fn] then
        error("operation not available: " .. tostring(request.lib) .. "." .. tostring(request.fn))
    end
    local value, status = module[request.fn](unpack(args))
    return value, status, kcapp._result_kind(request.lib, request.fn)
end

local function dispatch(ctx, method, params_json, output, userdata)
    local state = states[tostring(ctx)]
    if not state then return KC_WVW_ERROR end

    local method_name = method ~= nil and method ~= ffi.NULL and ffi.string(method) or ""
    if method_name ~= "kcapp_bridge" then
        return failure(state, output, "METHOD_NOT_FOUND", "Bridge method not available")
    end

    local source = params_json ~= nil and params_json ~= ffi.NULL and ffi.string(params_json) or "{}"
    local ok, request = pcall(json.decode, source)
    if not ok or type(request) ~= "table" then
        return failure(state, output, "INVALID_PARAMS", "Invalid bridge request")
    end

    local call_ok, value, status, result_kind = pcall(call_operation, state, request)
    if not call_ok then
        return failure(state, output, "EXEC_ERROR", tostring(value))
    end
    if value == nil and status ~= nil then
        return failure(
            state,
            output,
            "KCLIB_STATUS",
            "kclib operation returned status " .. tostring(status),
            status
        )
    end

    local transport_ok, transported = pcall(transport_out, state, value, result_kind)
    if not transport_ok then
        return failure(state, output, "EXEC_ERROR", tostring(transported))
    end

    result(state, output, transported)
    return KC_WVW_OK
end

local function has_callback(signature)
    for _, parameter in ipairs(signature or {}) do
        if parameter.kind == "callback" then return true end
    end
    return false
end

local function facade(libraries)
    local lines = {
        "(function(){",
        "if(!window.NativeBridge||!window.NativeBridge.kcapp_bridge){return;}",
        "var send=window.NativeBridge.kcapp_bridge;",
        "function encode(v){",
        "if(v&&v.__kcappObjectId){return {__kcapp_object:v.__kcappObjectId};}",
        "if(typeof ArrayBuffer!=='undefined'&&ArrayBuffer.isView&&ArrayBuffer.isView(v)){return {__kcapp_bytes:Array.prototype.slice.call(new Uint8Array(v.buffer,v.byteOffset,v.byteLength))};}",
        "if(Array.isArray(v)){return v.map(encode);}",
        "if(v&&typeof v==='object'){var o={};Object.keys(v).forEach(function(k){o[k]=encode(v[k]);});return o;}",
        "return v;",
        "}",
        "function invoke(req,args){req.args=Array.prototype.map.call(args,encode);return send(req).then(wrap);}",
        "function wrap(v){",
        "if(v&&v.__kcapp_bytes){return new Uint8Array(v.__kcapp_bytes);}",
        "if(Array.isArray(v)){return v.map(wrap);}",
        "if(v&&v.__kcapp_object){",
        "var o={};Object.defineProperty(o,'__kcappObjectId',{value:v.__kcapp_object});",
        "(v.__kcapp_methods||[]).forEach(function(name){o[name]=function(){return invoke({object:v.__kcapp_object,fn:name},arguments);};});",
        "return o;",
        "}",
        "if(v&&typeof v==='object'){Object.keys(v).forEach(function(k){v[k]=wrap(v[k]);});}",
        "return v;",
        "}"
    }

    for _, library in ipairs(libraries) do
        lines[#lines + 1] = "window.NativeBridge[" .. json.encode(library.name) .. "]={};"
        for key, value in pairs(library.constants) do
            lines[#lines + 1] =
                "window.NativeBridge[" .. json.encode(library.name) .. "][" ..
                json.encode(key) .. "]=" .. tostring(value) .. ";"
        end
        for _, method in ipairs(library.methods) do
            lines[#lines + 1] =
                "window.NativeBridge[" .. json.encode(library.name) .. "][" ..
                json.encode(method) .. "]=function(){return invoke({lib:" ..
                json.encode(library.name) .. ",fn:" .. json.encode(method) ..
                "},arguments);};"
        end
    end

    lines[#lines + 1] = "})();"
    return table.concat(lines)
end

function bridge.install(window, libraries)
    if not kcapp._is_object(window) or window._type ~= "kc_wvw_t" then
        error("kcapp.bridge: expected wvw window", 2)
    end
    if type(libraries) ~= "table" then
        error("kcapp.bridge: libraries must be a table", 2)
    end

    local state = {
        modules = {},
        methods = {},
        objects = {},
        object_ids = setmetatable({}, {__mode = "k"}),
        object_counter = 0
    }
    local exposed = {}

    for _, name in ipairs(libraries) do
        local module = kcapp.load(name)
        local description = kcapp._description(name)
        local methods = {}
        local allowed = {}
        local constants = {}

        for public_name in pairs(description.constants) do
            if type(module[public_name]) == "number" then
                constants[public_name] = module[public_name]
            end
        end

        for operation, info in pairs(description.functions) do
            if not info.receiver_type then
                local signature = kcapp._signature(name, operation)
                if not has_callback(signature) then
                    methods[#methods + 1] = operation
                    allowed[operation] = true
                end
            end
        end

        table.sort(methods)
        state.modules[name] = module
        state.methods[name] = allowed
        exposed[#exposed + 1] = {
            name = name,
            methods = methods,
            constants = constants
        }
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
    states[tostring(window._ptr)] = state

    local wvw = kcapp._raw("wvw")
    if wvw.kc_wvw_enable_bridge(window._ptr, options) ~= KC_WVW_OK then
        states[tostring(window._ptr)] = nil
        state.callback:free()
        error("kcapp.bridge: failed to enable WebView bridge", 2)
    end

    if wvw.kc_wvw_add_init_script(window._ptr, facade(exposed)) ~= KC_WVW_OK then
        states[tostring(window._ptr)] = nil
        state.callback:free()
        error("kcapp.bridge: failed to install JavaScript facade", 2)
    end

    return true
end

function bridge.release(window)
    if not kcapp._is_object(window) then return end
    local key = tostring(window._ptr)
    local state = states[key]
    if not state then return end
    states[key] = nil
    if state.callback then
        state.callback:free()
        state.callback = nil
    end
end

return bridge
