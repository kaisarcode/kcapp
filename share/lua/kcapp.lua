-- kcapp.lua
-- Summary: Loads kclib shared libraries and provides WebView bridge for kcapp applications.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local ffi = require("ffi")
local kcapp = {}

function kcapp.load(name)
    local path = "./lib/lib" .. name .. ".cdef"
    local definition, error_message = io.open(path, "r")

    if definition == nil then
        error("kcapp: cannot open " .. path .. ": " .. (error_message or "unknown error"), 2)
    end

    ffi.cdef(definition:read("*a"))
    definition:close()

    local extension = ".so"
    if ffi.os == "Windows" then
        extension = ".dll"
    elseif ffi.os == "OSX" then
        extension = ".dylib"
    end

    return ffi.load("./lib/lib" .. name .. extension)
end

function kcapp.bridge(window, libs)
    local bridge = require("bridge")
    return bridge.install(window, libs)
end

return kcapp
