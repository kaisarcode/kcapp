-- kcapp.lua
-- Summary: Projects kclib public ABIs into scripting-level Lua APIs.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local ffi = require("ffi")
local kcapp = {}

local raw_libraries = {}
local descriptions = {}
local modules = {}
local object_cache = setmetatable({}, {__mode = "v"})
local platform_cdef_ready = false

local scalar_types = {
    ["char"] = true,
    ["signed char"] = true,
    ["unsigned char"] = true,
    ["short"] = true,
    ["unsigned short"] = true,
    ["int"] = true,
    ["unsigned int"] = true,
    ["long"] = true,
    ["unsigned long"] = true,
    ["long long"] = true,
    ["unsigned long long"] = true,
    ["size_t"] = true,
    ["ssize_t"] = true,
    ["int8_t"] = true,
    ["uint8_t"] = true,
    ["int16_t"] = true,
    ["uint16_t"] = true,
    ["int32_t"] = true,
    ["uint32_t"] = true,
    ["int64_t"] = true,
    ["uint64_t"] = true,
    ["float"] = true,
    ["double"] = true
}

local function trim(value)
    return (value or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

local function canonical_type(value)
    value = trim(value)
    value = value:gsub("%s*%*%s*", " * ")
    return trim(value)
end

local function pointer_level(value)
    local _, count = canonical_type(value):gsub("%*", "")
    return count
end

local function base_type(value)
    value = canonical_type(value)
    value = value:gsub("%f[%a]const%f[%A]", "")
    value = value:gsub("%f[%a]volatile%f[%A]", "")
    value = value:gsub("%*", "")
    return trim(value)
end

local function is_const_type(value)
    return canonical_type(value):match("%f[%a]const%f[%A]") ~= nil
end

local function starts_with(value, prefix)
    return value:sub(1, #prefix) == prefix
end

local function split_top_level(source, separator)
    local parts = {}
    local start = 1
    local paren = 0
    local brace = 0
    local bracket = 0

    for index = 1, #source do
        local char = source:sub(index, index)
        if char == "(" then paren = paren + 1
        elseif char == ")" then paren = paren - 1
        elseif char == "{" then brace = brace + 1
        elseif char == "}" then brace = brace - 1
        elseif char == "[" then bracket = bracket + 1
        elseif char == "]" then bracket = bracket - 1
        elseif char == separator and paren == 0 and brace == 0 and bracket == 0 then
            parts[#parts + 1] = trim(source:sub(start, index - 1))
            start = index + 1
        end
    end

    local tail = trim(source:sub(start))
    if tail ~= "" then
        parts[#parts + 1] = tail
    end
    return parts
end

local function statements(source)
    local result = {}
    local current = {}
    local paren = 0
    local brace = 0
    local bracket = 0

    source = source:gsub("/%*.-%*/", " ")
    for index = 1, #source do
        local char = source:sub(index, index)
        current[#current + 1] = char
        if char == "(" then paren = paren + 1
        elseif char == ")" then paren = paren - 1
        elseif char == "{" then brace = brace + 1
        elseif char == "}" then brace = brace - 1
        elseif char == "[" then bracket = bracket + 1
        elseif char == "]" then bracket = bracket - 1
        elseif char == ";" and paren == 0 and brace == 0 and bracket == 0 then
            local statement = trim(table.concat(current):sub(1, -2))
            if statement ~= "" then
                result[#result + 1] = statement
            end
            current = {}
        end
    end
    return result
end

local function parse_decl(source)
    source = trim(source)
    local array = source:match("%[([^%]]+)%]%s*$")
    if array then
        source = trim(source:gsub("%[[^%]]+%]%s*$", ""))
    end

    local name = source:match("([%a_][%w_]*)%s*$")
    if not name then
        return nil
    end
    local kind = canonical_type(source:sub(1, #source - #name))
    return {
        name = name,
        type = kind,
        base = base_type(kind),
        pointers = pointer_level(kind),
        const = is_const_type(kind),
        array = array
    }
end

local function pair_name(pointer_name, scalar_name, suffix)
    if scalar_name == pointer_name .. suffix then
        return true
    end
    if pointer_name:sub(-1) == "s" and scalar_name == pointer_name:sub(1, -2) .. suffix then
        return true
    end
    if pointer_name == "data" and scalar_name == suffix:sub(2) then
        return true
    end
    return false
end

local function is_output(parameter)
    return parameter.name == "out" or starts_with(parameter.name, "out_")
end

local function output_name(parameter)
    if parameter.name == "out" then
        return "value"
    end
    return parameter.name:gsub("^out_", "")
end

local function library_extension()
    if ffi.os == "Windows" then return ".dll" end
    if ffi.os == "OSX" then return ".dylib" end
    return ".so"
end

local function read_definition(name)
    local path = "./lib/lib" .. name .. ".cdef"
    local file, message = io.open(path, "rb")
    if not file then
        error("kcapp: cannot open " .. path .. ": " .. (message or "unknown error"), 3)
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function parse_description(name, source)
    local description = {
        name = name,
        prefix = "kc_" .. name .. "_",
        structs = {},
        opaque = {},
        callbacks = {},
        functions = {},
        methods = {},
        constants = {}
    }

    for _, statement in ipairs(statements(source)) do
        local tag, body, typedef_name =
            statement:match("^typedef struct%s*([%w_]*)%s*{(.*)}%s*([%w_]+)$")
        if typedef_name then
            local fields = {}
            for _, field_source in ipairs(split_top_level(body, ";")) do
                local field = parse_decl(field_source)
                if field then
                    fields[#fields + 1] = field
                end
            end
            description.structs[typedef_name] = {
                name = typedef_name,
                tag = tag ~= "" and tag or nil,
                fields = fields
            }
        else
            local opaque_tag, opaque_name =
                statement:match("^typedef struct%s+([%w_]+)%s+([%w_]+)$")
            if opaque_name then
                description.opaque[opaque_name] = {
                    name = opaque_name,
                    tag = opaque_tag
                }
            else
                local callback_return, callback_name, callback_params =
                    statement:match("^typedef%s+(.+)%(%s*%*%s*([%w_]+)%s*%)%s*%((.*)%)$")
                if callback_name then
                    local params = {}
                    callback_params = trim(callback_params)
                    if callback_params ~= "" and callback_params ~= "void" then
                        for _, item in ipairs(split_top_level(callback_params, ",")) do
                            local parameter = parse_decl(item)
                            if parameter then
                                params[#params + 1] = parameter
                            end
                        end
                    end
                    description.callbacks[callback_name] = {
                        name = callback_name,
                        return_type = canonical_type(callback_return),
                        parameters = params
                    }
                elseif not statement:match("^enum%s*{") then
                    local start_at, end_at = statement:find("kc_[%w_]+%s*%(")
                    local symbol
                    local return_type
                    local params
                    if start_at then
                        symbol = statement:sub(start_at, end_at):match("^(kc_[%w_]+)")
                        return_type = trim(statement:sub(1, start_at - 1))
                        params = statement:sub(end_at + 1):match("^(.*)%)$")
                    end
                    if symbol and params and starts_with(symbol, description.prefix) then
                        local parameters = {}
                        params = trim(params)
                        if params ~= "" and params ~= "void" then
                            for _, item in ipairs(split_top_level(params, ",")) do
                                local parameter = parse_decl(item)
                                if parameter then
                                    parameters[#parameters + 1] = parameter
                                end
                            end
                        end
                        local short = symbol:sub(#description.prefix + 1)
                        description.functions[short] = {
                            symbol = symbol,
                            name = short,
                            return_type = canonical_type(return_type),
                            return_base = base_type(return_type),
                            return_pointers = pointer_level(return_type),
                            return_const = is_const_type(return_type),
                            parameters = parameters
                        }
                    end
                end
            end
        end
    end

    local constant_prefix = "KC_" .. name:upper() .. "_"
    for constant in source:gmatch("([A-Z][A-Z0-9_]+)%s*=") do
        if starts_with(constant, constant_prefix) then
            description.constants[constant:sub(#constant_prefix + 1)] = constant
        end
    end

    for _, opaque in pairs(description.opaque) do
        local stem = opaque.name:gsub("_t$", "")
        local prefix = "kc_" .. name
        if starts_with(stem, prefix) then
            stem = stem:sub(#prefix + 1):gsub("^_", "")
        end
        opaque.stem = stem
        description.methods[opaque.name] = {}
    end

    for _, info in pairs(description.functions) do
        local first = info.parameters[1]
        if first and first.pointers == 1 and description.opaque[first.base] and not is_output(first) then
            local opaque = description.opaque[first.base]
            local method = info.name
            if opaque.stem ~= "" and starts_with(method, opaque.stem .. "_") then
                method = method:sub(#opaque.stem + 2)
            end
            info.receiver_type = first.base
            info.method_name = method
            description.methods[first.base][method] = info
        end
    end

    return description
end

local function raw_library(name)
    if raw_libraries[name] then
        return raw_libraries[name]
    end
    local source = read_definition(name)
    ffi.cdef(source)
    local lib = ffi.load("./lib/lib" .. name .. library_extension())
    raw_libraries[name] = lib
    descriptions[name] = parse_description(name, source)
    return lib
end

local function description(name)
    raw_library(name)
    return descriptions[name]
end

local function cdata_null(value)
    return value == nil or value == ffi.NULL
end

local function append_all(destination, source)
    for _, value in ipairs(source or {}) do
        destination[#destination + 1] = value
    end
end

local function pointer_key(value)
    if cdata_null(value) then return nil end
    return tostring(ffi.cast("void *", value))
end

local object_mt = {}

local function object_methods(object)
    return description(object._lib).methods[object._type] or {}
end

local function object_valid(object)
    if type(object) ~= "table" or not object._kcapp_object then
        return false
    end
    if object._ptr == nil or object._ptr == ffi.NULL then
        return false
    end
    return true
end

local invoke

local function wrap_object(lib_name, type_name, ptr, owned)
    if cdata_null(ptr) then
        return nil
    end

    local key = lib_name .. ":" .. type_name .. ":" .. pointer_key(ptr)
    local existing = object_cache[key]
    if existing and object_valid(existing) then
        if owned then existing._owned = true end
        return existing
    end

    local object = {
        _kcapp_object = true,
        _lib = lib_name,
        _type = type_name,
        _ptr = ptr,
        _owned = owned and true or false,
        _callbacks = {},
        _cache_key = key
    }
    setmetatable(object, object_mt)
    object_cache[key] = object
    return object
end

local function invalidate_object(object)
    if type(object) ~= "table" then return end
    if object._cache_key then
        object_cache[object._cache_key] = nil
    end
    object._callbacks = {}
    object._ptr = nil
end

object_mt.__index = function(object, key)
    local info = object_methods(object)[key]
    if not info then return nil end
    local method = function(self, ...)
        if self ~= object then
            error("kcapp: invalid method receiver", 2)
        end
        if not object_valid(self) then
            error("kcapp: native object is closed", 2)
        end
        return invoke(self._lib, info, self, ...)
    end
    rawset(object, key, method)
    return method
end

object_mt.__tostring = function(object)
    return string.format("%s.%s", object._lib or "kcapp", object._type or "object")
end

local function struct_pair(fields, index)
    local field = fields[index]
    local next_field = fields[index + 1]
    if not field or not next_field then return nil end
    if field.pointers == 0 or next_field.pointers ~= 0 then return nil end
    if pair_name(field.name, next_field.name, "_size") then
        return "size", next_field
    end
    if pair_name(field.name, next_field.name, "_count") then
        return "count", next_field
    end
    return nil
end

local function function_pair(parameters, index)
    local parameter = parameters[index]
    local next_parameter = parameters[index + 1]
    if not parameter or not next_parameter then return nil end
    if parameter.pointers == 0 or next_parameter.pointers > 1 then return nil end

    if is_output(parameter) and is_output(next_parameter) then
        if next_parameter.name == "out_size" then
            return "size", next_parameter
        end
        if next_parameter.name == "out_count" then
            return "count", next_parameter
        end
    end
    if pair_name(parameter.name:gsub("^out_", ""),
        next_parameter.name:gsub("^out_", ""), "_size") then
        return "size", next_parameter
    end
    if pair_name(parameter.name:gsub("^out_", ""),
        next_parameter.name:gsub("^out_", ""), "_count") then
        return "count", next_parameter
    end
    if parameter.name == "data" and next_parameter.name == "size" then
        return "size", next_parameter
    end
    return nil
end

local function scalar_value(value)
    if type(value) == "boolean" then
        return value and 1 or 0
    end
    return value
end

local function scalar_from_c(value)
    if type(value) == "number" then return value end
    return tonumber(value)
end

local fill_struct
local struct_to_lua
local make_callback
local free_pointer

local function allocate_scalar_pointer(type_name, value, keep)
    local cell = ffi.new(type_name .. "[1]")
    cell[0] = scalar_value(value)
    keep[#keep + 1] = cell
    return cell
end

local function allocate_bytes(value, keep)
    if value == nil then return nil, 0 end
    if type(value) ~= "string" then
        error("kcapp: binary value must be a string", 3)
    end
    if #value == 0 then
        local empty = ffi.new("uint8_t[1]")
        keep[#keep + 1] = empty
        return empty, 0
    end
    local buffer = ffi.new("uint8_t[?]", #value)
    ffi.copy(buffer, value, #value)
    keep[#keep + 1] = buffer
    return buffer, #value
end

local function allocate_scalar_array(type_name, values, keep)
    if type(values) ~= "table" then
        error("kcapp: expected array table", 3)
    end
    if #values == 0 then return nil, 0 end
    local array = ffi.new(type_name .. "[?]", #values)
    for index, value in ipairs(values) do
        array[index - 1] = scalar_value(value)
    end
    keep[#keep + 1] = array
    return array, #values
end

local function allocate_string_array(values, keep)
    if type(values) ~= "table" then
        error("kcapp: expected string array table", 3)
    end
    if #values == 0 then return nil, 0 end
    local array = ffi.new("const char *[?]", #values)
    keep[#keep + 1] = array
    for index, value in ipairs(values) do
        if type(value) ~= "string" then
            error("kcapp: expected string array item", 3)
        end
        array[index - 1] = value
    end
    return array, #values
end

local function allocate_struct_array(lib_name, type_name, values, keep)
    if type(values) ~= "table" then
        error("kcapp: expected array table", 3)
    end
    if #values == 0 then return nil, 0 end
    local array = ffi.new(type_name .. "[?]", #values)
    keep[#keep + 1] = array
    for index, value in ipairs(values) do
        fill_struct(lib_name, type_name, array[index - 1], value or {}, keep)
    end
    return array, #values
end

fill_struct = function(lib_name, type_name, target, value, keep)
    if type(value) ~= "table" then
        error("kcapp: expected table for " .. type_name, 3)
    end
    local desc = description(lib_name)
    local struct = desc.structs[type_name]
    if not struct then
        error("kcapp: unknown public struct " .. type_name, 3)
    end

    local index = 1
    while index <= #struct.fields do
        local field = struct.fields[index]
        local pair_kind, count_field = struct_pair(struct.fields, index)
        local item = value[field.name]

        if pair_kind then
            if field.base == "void" then
                local pointer, count = allocate_bytes(item, keep)
                target[field.name] = pointer
                target[count_field.name] = count
            elseif field.base == "char" and field.pointers >= 2 then
                local pointer, count = allocate_string_array(item or {}, keep)
                target[field.name] = pointer
                target[count_field.name] = count
            elseif desc.structs[field.base] then
                local pointer, count = allocate_struct_array(lib_name, field.base, item or {}, keep)
                target[field.name] = pointer
                target[count_field.name] = count
            elseif scalar_types[field.base] then
                local pointer, count = allocate_scalar_array(field.base, item or {}, keep)
                target[field.name] = pointer
                target[count_field.name] = count
            else
                error("kcapp: unsupported paired struct field " .. field.name, 3)
            end
            index = index + 2
        elseif field.array then
            if field.base == "char" and type(item) == "string" then
                ffi.copy(target[field.name], item, math.min(#item, ffi.sizeof(target[field.name]) - 1))
            elseif item ~= nil then
                error("kcapp: unsupported fixed array field " .. field.name, 3)
            end
            index = index + 1
        elseif desc.callbacks[field.base] and field.pointers == 0 then
            if item ~= nil then
                target[field.name] = make_callback(lib_name, field.base, item, keep)
            end
            index = index + 1
        elseif field.pointers == 0 then
            if item ~= nil then
                target[field.name] = scalar_value(item)
            end
            index = index + 1
        elseif field.base == "char" and field.pointers == 1 then
            target[field.name] = item
            index = index + 1
        elseif desc.opaque[field.base] and field.pointers == 1 then
            if item ~= nil then
                if not object_valid(item) or item._type ~= field.base then
                    error("kcapp: expected " .. field.base .. " object", 3)
                end
                target[field.name] = item._ptr
            end
            index = index + 1
        elseif scalar_types[field.base] and field.pointers == 1 then
            if item ~= nil then
                target[field.name] = allocate_scalar_pointer(field.base, item, keep)
            end
            index = index + 1
        elseif field.base == "void" and field.pointers == 1 then
            if item ~= nil then
                target[field.name] = item
            end
            index = index + 1
        else
            error("kcapp: unsupported public struct field " .. field.name, 3)
        end
    end
end

local function marshal_struct(lib_name, type_name, value, keep)
    if value == nil then return nil end
    local pointer = ffi.new(type_name .. "[1]")
    keep[#keep + 1] = pointer
    fill_struct(lib_name, type_name, pointer[0], value, keep)
    return pointer
end

struct_to_lua = function(lib_name, type_name, value)
    local desc = description(lib_name)
    local struct = desc.structs[type_name]
    if not struct then
        error("kcapp: unknown public struct " .. type_name, 3)
    end

    local result = {}
    local index = 1
    while index <= #struct.fields do
        local field = struct.fields[index]
        local pair_kind, count_field = struct_pair(struct.fields, index)

        if pair_kind then
            local count = scalar_from_c(value[count_field.name])
            local pointer = value[field.name]
            if field.base == "void" then
                result[field.name] = cdata_null(pointer) and nil or ffi.string(pointer, count)
            elseif desc.structs[field.base] then
                local items = {}
                if not cdata_null(pointer) then
                    for item_index = 0, count - 1 do
                        items[#items + 1] = struct_to_lua(lib_name, field.base, pointer[item_index])
                    end
                end
                result[field.name] = items
            elseif scalar_types[field.base] then
                local items = {}
                if not cdata_null(pointer) then
                    for item_index = 0, count - 1 do
                        items[#items + 1] = scalar_from_c(pointer[item_index])
                    end
                end
                result[field.name] = items
            end
            index = index + 2
        elseif field.array then
            if field.base == "char" then
                result[field.name] = ffi.string(value[field.name])
            end
            index = index + 1
        elseif field.pointers == 0 then
            result[field.name] = scalar_from_c(value[field.name])
            index = index + 1
        elseif field.base == "char" and field.pointers == 1 then
            local pointer = value[field.name]
            result[field.name] = cdata_null(pointer) and nil or ffi.string(pointer)
            index = index + 1
        elseif desc.opaque[field.base] and field.pointers == 1 then
            local pointer = value[field.name]
            result[field.name] = cdata_null(pointer) and nil or wrap_object(lib_name, field.base, pointer, false)
            index = index + 1
        else
            index = index + 1
        end
    end
    return result
end

local function callback_arguments(lib_name, callback, native_args)
    local desc = description(lib_name)
    local values = {}
    local index = 1
    while index <= #callback.parameters do
        local parameter = callback.parameters[index]
        local pair_kind, count_parameter = function_pair(callback.parameters, index)
        local native = native_args[index]

        if parameter.name == "userdata" then
            index = index + 1
        elseif pair_kind and parameter.base == "void" then
            local count = scalar_from_c(native_args[index + 1])
            local value = cdata_null(native) and nil or ffi.string(native, count)
            values[#values + 1] = value
            if not parameter.const and not cdata_null(native) then
                free_pointer(lib_name, native)
            end
            index = index + 2
        elseif parameter.pointers == 1 and desc.structs[parameter.base] then
            values[#values + 1] = cdata_null(native) and nil or struct_to_lua(lib_name, parameter.base, native[0])
            index = index + 1
        elseif parameter.pointers == 1 and desc.opaque[parameter.base] then
            values[#values + 1] = cdata_null(native) and nil or wrap_object(lib_name, parameter.base, native, false)
            index = index + 1
        elseif parameter.base == "char" and parameter.pointers == 1 then
            values[#values + 1] = cdata_null(native) and nil or ffi.string(native)
            index = index + 1
        elseif parameter.pointers == 0 and scalar_types[parameter.base] then
            values[#values + 1] = scalar_from_c(native)
            index = index + 1
        else
            values[#values + 1] = native
            index = index + 1
        end
    end
    return values
end

make_callback = function(lib_name, type_name, handler, keep)
    if handler == nil then return nil end
    if type(handler) ~= "function" then
        error("kcapp: callback must be a function", 3)
    end

    local desc = description(lib_name)
    local callback = desc.callbacks[type_name]
    if not callback then
        error("kcapp: unknown callback type " .. type_name, 3)
    end

    local c_callback
    c_callback = ffi.cast(type_name, function(...)
        local native_args = {...}
        local values = callback_arguments(lib_name, callback, native_args)
        local ok, result = pcall(handler, unpack(values))
        if not ok then
            io.stderr:write("kcapp callback error: " .. tostring(result) .. "\n")
            if base_type(callback.return_type) ~= "void" then return 0 end
            return
        end
        if base_type(callback.return_type) == "void" then
            return
        end
        return scalar_value(result or 0)
    end)
    keep._callbacks = keep._callbacks or {}
    keep._callbacks[#keep._callbacks + 1] = c_callback
    return c_callback
end

local function marshal_input(lib_name, parameter, value, keep)
    local desc = description(lib_name)
    if desc.callbacks[parameter.base] and parameter.pointers == 0 then
        return make_callback(lib_name, parameter.base, value, keep)
    end
    if parameter.pointers == 0 then
        if scalar_types[parameter.base] then
            return scalar_value(value)
        end
        return value
    end
    if parameter.base == "char" and parameter.pointers == 1 then
        if value ~= nil and type(value) ~= "string" then
            error("kcapp: expected string for " .. parameter.name, 3)
        end
        return value
    end
    if desc.opaque[parameter.base] and parameter.pointers == 1 then
        if not object_valid(value) or value._type ~= parameter.base then
            error("kcapp: expected " .. parameter.base .. " object", 3)
        end
        return value._ptr
    end
    if desc.structs[parameter.base] and parameter.pointers == 1 then
        return marshal_struct(lib_name, parameter.base, value, keep)
    end
    if scalar_types[parameter.base] and parameter.pointers == 1 then
        if type(value) == "table" then
            local array = allocate_scalar_array(parameter.base, value, keep)
            return array
        end
        return allocate_scalar_pointer(parameter.base, value, keep)
    end
    if parameter.base == "void" and parameter.pointers == 1 then
        local pointer = allocate_bytes(value, keep)
        return pointer
    end
    return value
end

local function allocate_output(lib_name, parameter, keep)
    local desc = description(lib_name)
    local type_name

    if parameter.pointers < 1 then
        error("kcapp: output parameter is not a pointer: " .. parameter.name, 3)
    end

    type_name = canonical_type(parameter.type):gsub("%s*%*%s*$", "") .. "[1]"

    if desc.callbacks[parameter.base] then
        error("kcapp: callback output is unsupported", 3)
    end

    local cell = ffi.new(type_name)
    keep[#keep + 1] = cell
    return cell
end

free_pointer = function(lib_name, pointer)
    if cdata_null(pointer) then return end
    local desc = description(lib_name)
    local info = desc.functions.free
    if info then
        raw_library(lib_name)[info.symbol](pointer)
    end
end

local function convert_pointer_output(lib_name, parameter, pointer, count, owned)
    local desc = description(lib_name)
    if cdata_null(pointer) then
        if count ~= nil then
            if parameter.base == "void" then return "" end
            return {}
        end
        return nil
    end

    if desc.opaque[parameter.base] then
        return wrap_object(lib_name, parameter.base, pointer, true)
    end

    if count ~= nil then
        if parameter.base == "void" then
            local data = ffi.string(pointer, count)
            if owned then free_pointer(lib_name, pointer) end
            return data
        end
        if parameter.base == "char" and parameter.pointers == 2 then
            local items = {}
            for index = 0, count - 1 do
                local item = pointer[index]
                items[#items + 1] = cdata_null(item) and nil or ffi.string(item)
            end
            if owned then free_pointer(lib_name, pointer) end
            return items
        end
        if desc.structs[parameter.base] then
            local items = {}
            for index = 0, count - 1 do
                items[#items + 1] = struct_to_lua(lib_name, parameter.base, pointer[index])
            end
            if owned then free_pointer(lib_name, pointer) end
            return items
        end
        if scalar_types[parameter.base] then
            local items = {}
            for index = 0, count - 1 do
                items[#items + 1] = scalar_from_c(pointer[index])
            end
            if owned then free_pointer(lib_name, pointer) end
            return items
        end
    end

    if parameter.base == "char" then
        local value = ffi.string(pointer)
        if owned then free_pointer(lib_name, pointer) end
        return value
    end
    if desc.structs[parameter.base] then
        local value = struct_to_lua(lib_name, parameter.base, pointer[0])
        if owned then free_pointer(lib_name, pointer) end
        return value
    end
    if scalar_types[parameter.base] then
        return scalar_from_c(pointer[0])
    end
    return pointer
end

local function direct_result(lib_name, info, result, output_cells)
    local desc = description(lib_name)
    if info.return_pointers == 0 then
        if info.return_base == "void" then return nil end
        if scalar_types[info.return_base] then return scalar_from_c(result) end
        return result
    end

    if info.return_base == "char" and info.return_pointers == 1 then
        if cdata_null(result) then return nil end
        local value = ffi.string(result)
        if not info.return_const then free_pointer(lib_name, result) end
        return value
    end

    if info.return_base == "void" and info.return_pointers == 1 then
        local size
        for _, output in ipairs(output_cells) do
            if output.parameter.name == "out_size" then
                size = scalar_from_c(output.cell[0])
                break
            end
        end
        if size ~= nil then
            if cdata_null(result) then return nil end
            local value = ffi.string(result, size)
            if not info.return_const then free_pointer(lib_name, result) end
            return value
        end
    end

    if desc.opaque[info.return_base] then
        return wrap_object(lib_name, info.return_base, result, not info.return_const)
    end
    return result
end

local function plan_call(lib_name, info, receiver, script_args)
    local desc = description(lib_name)
    local native_args = {}
    local keep = {}
    local output_cells = {}
    local script_index = 1
    local parameter_index = 1

    while parameter_index <= #info.parameters do
        local parameter = info.parameters[parameter_index]
        local pair_kind, pair_parameter = function_pair(info.parameters, parameter_index)

        if parameter_index == 1 and info.receiver_type then
            native_args[#native_args + 1] = receiver._ptr
            parameter_index = parameter_index + 1
        elseif is_output(parameter) then
            local cell = allocate_output(lib_name, parameter, keep)
            native_args[#native_args + 1] = cell
            output_cells[#output_cells + 1] = {
                parameter = parameter,
                cell = cell,
                pair_kind = pair_kind,
                pair_parameter = pair_parameter
            }
            if pair_kind and pair_parameter and is_output(pair_parameter) then
                local count_cell = allocate_output(lib_name, pair_parameter, keep)
                native_args[#native_args + 1] = count_cell
                output_cells[#output_cells].count_cell = count_cell
                parameter_index = parameter_index + 2
            else
                parameter_index = parameter_index + 1
            end
        elseif parameter.name == "userdata" then
            native_args[#native_args + 1] = nil
            parameter_index = parameter_index + 1
        elseif pair_kind and pair_parameter and pair_parameter.pointers == 0 then
            local value = script_args[script_index]
            script_index = script_index + 1
            if parameter.base == "void" then
                local pointer, count = allocate_bytes(value, keep)
                native_args[#native_args + 1] = pointer
                native_args[#native_args + 1] = count
            elseif desc.structs[parameter.base] then
                local pointer, count = allocate_struct_array(lib_name, parameter.base, value or {}, keep)
                native_args[#native_args + 1] = pointer
                native_args[#native_args + 1] = count
            elseif scalar_types[parameter.base] then
                local pointer, count = allocate_scalar_array(parameter.base, value or {}, keep)
                native_args[#native_args + 1] = pointer
                native_args[#native_args + 1] = count
            else
                native_args[#native_args + 1] = marshal_input(lib_name, parameter, value, keep)
                native_args[#native_args + 1] = #value
            end
            parameter_index = parameter_index + 2
        else
            local value = script_args[script_index]
            script_index = script_index + 1
            native_args[#native_args + 1] = marshal_input(lib_name, parameter, value, keep)
            parameter_index = parameter_index + 1
        end
    end

    if script_index <= #script_args then
        error("kcapp: too many arguments for " .. lib_name .. "." .. info.name, 3)
    end

    return native_args, keep, output_cells
end

local function extract_outputs(lib_name, outputs)
    local values = {}
    local names = {}

    for _, output in ipairs(outputs) do
        local parameter = output.parameter
        local pointer
        if parameter.pointers == 1 then
            pointer = output.cell
        else
            pointer = output.cell[0]
        end

        local count
        if output.count_cell then
            count = scalar_from_c(output.count_cell[0])
        end

        local owned = not parameter.const and parameter.pointers >= 2
        local value
        if parameter.pointers == 1 and scalar_types[parameter.base] then
            value = scalar_from_c(output.cell[0])
        elseif parameter.pointers == 1 and description(lib_name).structs[parameter.base] then
            value = struct_to_lua(lib_name, parameter.base, output.cell[0])
        else
            value = convert_pointer_output(lib_name, parameter, pointer, count, owned)
        end

        values[#values + 1] = value
        names[#names + 1] = output_name(parameter)
    end

    if #values == 0 then return nil end
    if #values == 1 then return values[1] end

    local result = {}
    for index, value in ipairs(values) do
        result[names[index]] = value
    end
    return result
end

invoke = function(lib_name, info, receiver, ...)
    local script_args = {...}
    local native_args, keep, outputs = plan_call(lib_name, info, receiver, script_args)
    local lib = raw_library(lib_name)
    local result = lib[info.symbol](unpack(native_args))

    local has_outputs = #outputs > 0
    local status = nil
    if info.return_pointers == 0 and info.return_base == "int" and has_outputs then
        status = scalar_from_c(result)
        if status ~= 0 then
            return nil, status
        end
    end

    local value
    if has_outputs then
        if info.return_pointers == 1 and info.return_base == "void" then
            value = direct_result(lib_name, info, result, outputs)
        else
            value = extract_outputs(lib_name, outputs)
        end
    else
        value = direct_result(lib_name, info, result, outputs)
    end

    local target = nil
    if type(value) == "table" and value._kcapp_object then
        target = value
    elseif receiver then
        target = receiver
    elseif type(value) == "table" then
        for _, item in pairs(value) do
            if type(item) == "table" and item._kcapp_object then
                target = item
                break
            end
        end
    end

    if target and keep._callbacks then
        append_all(target._callbacks, keep._callbacks)
    end

    if receiver and (info.method_name == "close" or info.method_name == "remove") then
        invalidate_object(receiver)
    end

    return value
end

local function script_signature(lib_name, info)
    local desc = description(lib_name)
    local parameters = {}
    local index = 1
    while index <= #info.parameters do
        local parameter = info.parameters[index]
        local pair_kind, pair_parameter = function_pair(info.parameters, index)
        if index == 1 and info.receiver_type then
            index = index + 1
        elseif is_output(parameter) then
            if pair_kind and pair_parameter and is_output(pair_parameter) then
                index = index + 2
            else
                index = index + 1
            end
        elseif parameter.name == "userdata" then
            index = index + 1
        else
            local kind = "value"
            if desc.callbacks[parameter.base] then kind = "callback"
            elseif desc.structs[parameter.base] then kind = pair_kind and "array" or "object"
            elseif desc.opaque[parameter.base] then kind = "handle"
            elseif parameter.base == "void" and parameter.pointers == 1 then kind = "binary"
            elseif parameter.base == "char" and parameter.pointers == 1 then kind = "string"
            elseif pair_kind then kind = "array"
            end
            parameters[#parameters + 1] = {name = parameter.name, kind = kind}
            index = index + (pair_kind and pair_parameter and pair_parameter.pointers == 0 and 2 or 1)
        end
    end
    return parameters
end

local function module_for(name)
    local desc = description(name)
    local module = {}

    for public_name, constant_name in pairs(desc.constants) do
        local ok, value = pcall(function() return tonumber(ffi.C[constant_name]) end)
        if ok then module[public_name] = value end
    end

    setmetatable(module, {
        __index = function(_, key)
            local info = desc.functions[key]
            if not info or info.receiver_type then
                return nil
            end
            local fn = function(...)
                return invoke(name, info, nil, ...)
            end
            rawset(module, key, fn)
            return fn
        end
    })

    modules[name] = module
    return module
end

function kcapp.load(name)
    if modules[name] then return modules[name] end
    return module_for(name)
end

local function ensure_platform_cdef()
    if platform_cdef_ready then return end
    if ffi.os == "Windows" then
        ffi.cdef[[char *_getcwd(char *buffer, int maxlen);
                  void Sleep(unsigned long milliseconds);]]
    else
        ffi.cdef[[char *getcwd(char *buffer, size_t size);
                  int usleep(unsigned int usec);]]
    end
    platform_cdef_ready = true
end

local function file_url(path)
    if path:match("^%a[%w+.-]*://") then return path end
    ensure_platform_cdef()

    local buffer = ffi.new("char[4096]")
    local cwd
    if ffi.os == "Windows" then
        cwd = ffi.C._getcwd(buffer, 4096)
    else
        cwd = ffi.C.getcwd(buffer, 4096)
    end
    if cdata_null(cwd) then
        error("kcapp: cannot resolve application directory", 3)
    end

    local root = ffi.string(cwd)
    if ffi.os == "Windows" then
        root = root:gsub("\\", "/")
        return "file:///" .. root .. "/" .. path
    end
    return "file://" .. root .. "/" .. path
end

function kcapp.open(options)
    options = options or {}
    local copy = {}
    for key, value in pairs(options) do copy[key] = value end
    copy.url = file_url(copy.url or "src/www/index.html")

    local window, status = kcapp.load("wvw").open(copy)
    if not window then
        error("kcapp: cannot open window (status " .. tostring(status) .. ")", 2)
    end
    return window
end

function kcapp.run(window)
    if not object_valid(window) or window._type ~= "kc_wvw_t" then
        error("kcapp.run: expected wvw window", 2)
    end

    ensure_platform_cdef()
    local wvw = raw_library("wvw")
    while wvw.kc_wvw_is_visible(window._ptr) == 1 do
        if ffi.os == "Windows" then
            ffi.C.Sleep(50)
        else
            ffi.C.usleep(50000)
        end
    end

    local loaded_bridge = package.loaded.bridge
    if loaded_bridge and loaded_bridge.release then
        loaded_bridge.release(window)
    end
    if object_valid(window) then
        window:close()
    end
end

function kcapp.bridge(window, libraries)
    return require("bridge").install(window, libraries)
end

function kcapp._raw(name)
    return raw_library(name)
end

function kcapp._description(name)
    return description(name)
end

function kcapp._is_object(value)
    return object_valid(value)
end

function kcapp._object_methods(value)
    if not object_valid(value) then return {} end
    local methods = {}
    for name in pairs(object_methods(value)) do
        methods[#methods + 1] = name
    end
    table.sort(methods)
    return methods
end

function kcapp._signature(name, operation, type_name)
    local desc = description(name)
    local info
    if type_name then
        info = desc.methods[type_name] and desc.methods[type_name][operation]
    else
        info = desc.functions[operation]
    end
    if not info then return nil end
    return script_signature(name, info)
end

return kcapp
