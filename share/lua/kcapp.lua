-- kcapp.lua
-- Summary: Provides scripting-level kclib bindings and kcapp desktop runtime helpers.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local ffi = require("ffi")
local kcapp = {}

local raw_libraries = {}
local modules = {}
local descriptions = {}

local scalar_types = {
    ["int"] = true,
    ["unsigned int"] = true,
    ["short"] = true,
    ["unsigned short"] = true,
    ["long"] = true,
    ["unsigned long"] = true,
    ["size_t"] = true,
    ["uint16_t"] = true,
    ["uint32_t"] = true,
    ["uint64_t"] = true,
    ["int16_t"] = true,
    ["int32_t"] = true,
    ["int64_t"] = true,
    ["float"] = true,
    ["double"] = true
}

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end

local function library_extension()
    if ffi.os == "Windows" then
        return ".dll"
    end
    if ffi.os == "OSX" then
        return ".dylib"
    end
    return ".so"
end

local function read_definition(name)
    local path = "./lib/lib" .. name .. ".cdef"
    local file, message = io.open(path, "r")
    if not file then
        error("kcapp: cannot open " .. path .. ": " .. (message or "unknown error"), 3)
    end
    local source = file:read("*a")
    file:close()
    return source
end

local function split_parameters(source)
    local parameters = {}
    source = trim(source or "")
    if source == "" or source == "void" then
        return parameters
    end
    for parameter in source:gmatch("[^,]+") do
        parameters[#parameters + 1] = trim(parameter)
    end
    return parameters
end

local function parameter_type(parameter)
    local value = trim(parameter)
    local without_name = value:match("^(.-[%*%s])[%a_][%w_]*$")
    if without_name then
        return trim(without_name)
    end
    return value
end

local function classify_type(value)
    value = trim(value)
    if value == "void" then
        return "void"
    end
    if value == "const char *" then
        return "string"
    end
    if scalar_types[value] then
        return "number"
    end
    return "complex"
end

local function parse_functions(name, source)
    local functions = {}
    local prefix = "kc_" .. name .. "_"
    local statement = ""

    source = source:gsub("/%*.-%*/", " ")
    for line in source:gmatch("[^\r\n]+") do
        statement = statement .. " " .. trim(line)
        while true do
            local finish = statement:find(";", 1, true)
            if not finish then
                break
            end
            local declaration = trim(statement:sub(1, finish - 1))
            statement = statement:sub(finish + 1)

            if not declaration:match("^typedef") and not declaration:match("^enum") then
                local start_at, end_at = declaration:find("kc_[%w_]+%s*%(")
                if start_at then
                    local symbol = declaration:sub(start_at, end_at):match("^(kc_[%w_]+)")
                    local return_type = trim(declaration:sub(1, start_at - 1))
                    local params = declaration:sub(end_at + 1):match("^(.*)%)$")
                    if symbol and params and symbol:sub(1, #prefix) == prefix then
                        local item = {
                            symbol = symbol,
                            name = symbol:sub(#prefix + 1),
                            return_type = return_type,
                            parameters = split_parameters(params)
                        }
                        item.return_kind = classify_type(item.return_type)
                        item.parameter_kinds = {}
                        item.bridgeable = item.return_kind ~= "complex"
                        for index, parameter in ipairs(item.parameters) do
                            local kind = classify_type(parameter_type(parameter))
                            item.parameter_kinds[index] = kind
                            if kind == "complex" then
                                item.bridgeable = false
                            end
                        end
                        functions[item.name] = item
                    end
                end
            end
        end
    end
    return functions
end

local function raw_library(name)
    if raw_libraries[name] then
        return raw_libraries[name]
    end

    local source = read_definition(name)
    ffi.cdef(source)
    local lib = ffi.load("./lib/lib" .. name .. library_extension())
    raw_libraries[name] = lib
    descriptions[name] = {
        source = source,
        functions = parse_functions(name, source)
    }
    return lib
end

local function normalize_result(kind, value)
    if kind == "void" then
        return nil
    end
    if kind == "string" then
        if value == nil or value == ffi.NULL then
            return nil
        end
        return ffi.string(value)
    end
    if kind == "number" then
        return tonumber(value)
    end
    return value
end

local function call_simple(name, info, ...)
    local lib = raw_library(name)
    return normalize_result(info.return_kind, lib[info.symbol](...))
end

local function module_for(name)
    raw_library(name)
    local description = descriptions[name]
    local module = {}

    setmetatable(module, {
        __index = function(_, key)
            local info = description.functions[key]
            if not info then
                return nil
            end
            if not info.bridgeable then
                error("kcapp: operation '" .. name .. "." .. key ..
                    "' requires structured binding support", 2)
            end
            local fn = function(...)
                return call_simple(name, info, ...)
            end
            rawset(module, key, fn)
            return fn
        end
    })

    modules[name] = module
    return module
end

local function file_url(path)
    if path:match("^%a[%w+.-]*://") then
        return path
    end

    ffi.cdef[[
#if defined(_WIN32)
        char *_getcwd(char *buffer, int maxlen);
#else
        char *getcwd(char *buffer, size_t size);
#endif
    ]]

    local buffer = ffi.new("char[4096]")
    local cwd
    if ffi.os == "Windows" then
        cwd = ffi.C._getcwd(buffer, 4096)
    else
        cwd = ffi.C.getcwd(buffer, 4096)
    end
    if cwd == nil or cwd == ffi.NULL then
        error("kcapp: cannot resolve application directory", 3)
    end

    local root = ffi.string(cwd)
    if ffi.os == "Windows" then
        root = root:gsub("\\", "/")
        return "file:///" .. root .. "/" .. path
    end
    return "file://" .. root .. "/" .. path
end

local function optional_int(value, keep)
    if value == nil then
        return nil
    end
    local pointer = ffi.new("int[1]", value and (value == true and 1 or value) or 0)
    keep[#keep + 1] = pointer
    return pointer
end

local function wvw_open(options)
    options = options or {}
    local wvw = raw_library("wvw")
    local keep = {}
    local native = ffi.new("kc_wvw_options_t")
    local url = file_url(options.url or "src/www/index.html")

    keep[#keep + 1] = url
    native.url = url
    native.title = options.title
    native.background = options.background
    native.width = optional_int(options.width, keep)
    native.height = optional_int(options.height, keep)
    native.posx = optional_int(options.posx, keep)
    native.posy = optional_int(options.posy, keep)
    native.fullscreen = optional_int(options.fullscreen, keep)
    native.borderless = optional_int(options.borderless, keep)
    native.always_on_top = optional_int(options.always_on_top, keep)
    native.click_through = optional_int(options.click_through, keep)
    native.no_focus = optional_int(options.no_focus, keep)

    local out = ffi.new("kc_wvw_t *[1]")
    if wvw.kc_wvw_open(out, native) ~= 0 then
        local message = wvw.kc_wvw_get_error(out[0])
        error("kcapp: cannot open window: " ..
            ((message ~= nil and message ~= ffi.NULL) and ffi.string(message) or "unknown error"), 2)
    end

    return {
        _wvw_ctx = out[0],
        _wvw_keep = keep
    }
end

local function install_wvw_surface(module)
    module.open = wvw_open
end

-- Load one kclib as a scripting-level Lua module.
-- @param name string kclib name
-- @return table natural Lua projection of the public kclib API
function kcapp.load(name)
    if modules[name] then
        return modules[name]
    end
    local module = module_for(name)
    if name == "wvw" then
        install_wvw_surface(module)
    end
    return module
end

-- Open the application's WebView through the wvw scripting binding.
-- @param options table window options
-- @return table kcapp window object
function kcapp.open(options)
    return kcapp.load("wvw").open(options)
end

-- Run one window until it is no longer visible, then close it.
-- @param window table kcapp window object
-- @return nil
function kcapp.run(window)
    if type(window) ~= "table" or not window._wvw_ctx then
        error("kcapp.run: invalid window", 2)
    end

    ffi.cdef[[
#if defined(_WIN32)
        void Sleep(unsigned long milliseconds);
#else
        int usleep(unsigned int usec);
#endif
    ]]

    local wvw = raw_library("wvw")
    while wvw.kc_wvw_is_visible(window._wvw_ctx) == 1 do
        if ffi.os == "Windows" then
            ffi.C.Sleep(50)
        else
            ffi.C.usleep(50000)
        end
    end
    wvw.kc_wvw_close(window._wvw_ctx)
    window._wvw_ctx = nil
end

-- Expose selected kclib scripting APIs to one WebView.
-- @param window table kcapp window object
-- @param libraries table array of kclib names
-- @return boolean true on success
function kcapp.bridge(window, libraries)
    return require("bridge").install(window, libraries)
end

function kcapp._raw(name)
    return raw_library(name)
end

function kcapp._description(name)
    raw_library(name)
    return descriptions[name]
end

return kcapp
