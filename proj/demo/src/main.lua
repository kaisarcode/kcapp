-- main.lua
-- Summary: kcapp demo application entry point.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local ffi = require("ffi")
local kcapp = require("kcapp")

if ffi.os == "Windows" then
    ffi.cdef[[void Sleep(unsigned long milliseconds);]]
else
    ffi.cdef[[int usleep(unsigned int usec);]]
end

local wvw = kcapp.load("wvw")
local redp2p = kcapp.load("redp2p")

local cwd_buffer = ffi.new("char[4096]")
local cwd
if ffi.os == "Windows" then
    ffi.cdef[[char *_getcwd(char *buffer, int maxlen);]]
    cwd = ffi.C._getcwd(cwd_buffer, 4096)
else
    ffi.cdef[[char *getcwd(char *buffer, size_t size);]]
    cwd = ffi.C.getcwd(cwd_buffer, 4096)
end
if cwd == nil or cwd == ffi.NULL then
    error("kcapp demo: cannot resolve application directory")
end

local url = "file://" .. ffi.string(cwd) .. "/src/www/index.html"
if ffi.os == "Windows" then
    url = "file:///" .. ffi.string(cwd):gsub("\\", "/") .. "/src/www/index.html"
end

local width = ffi.new("int[1]", 900)
local height = ffi.new("int[1]", 700)
local options = ffi.new("kc_wvw_options_t[1]")
options[0].url = url
options[0].title = "Demo"
options[0].background = "101418"
options[0].width = width
options[0].height = height

local ctx = ffi.new("kc_wvw_t *[1]")
if wvw.kc_wvw_open(ctx, options) ~= 0 then
    local err = ctx[0] ~= nil and wvw.kc_wvw_get_error(ctx[0]) or nil
    error("kcapp demo: failed to open window: " ..
        ((err ~= nil and err ~= ffi.NULL) and ffi.string(err) or "unknown error"))
end

local window = {
    _wvw_ctx = ctx[0]
}

kcapp.bridge(window, {
    redp2pVersion = function()
        return {
            version = tonumber(redp2p.kc_redp2p_version())
        }
    end
})

while wvw.kc_wvw_is_visible(ctx[0]) == 1 do
    if ffi.os == "Windows" then
        ffi.C.Sleep(50)
    else
        ffi.C.usleep(50000)
    end
end

wvw.kc_wvw_close(ctx[0])
