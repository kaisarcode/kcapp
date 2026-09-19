-- main.lua
-- Summary: kcapp demo application entry point.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local ffi = require("ffi")
local kcapp = require("kcapp")

ffi.cdef[[char *getcwd(char *buf, size_t size);]]

local wvw = kcapp.load("wvw")

local cwd = ffi.C.getcwd(ffi.new("char[4096]"), 4096)
local html_path = ffi.string(cwd) .. "/src/www/index.html"
local url = "file://" .. html_path

local opts = wvw.kc_wvw_options_default()
local url_buf = ffi.new("char[?]", #url + 1)
ffi.copy(url_buf, url)
opts.url = url_buf

local title_buf = ffi.new("char[?]", #"Demo" + 1)
ffi.copy(title_buf, "Demo")
opts.title = title_buf

local bg_buf = ffi.new("char[?]", #"101418" + 1)
ffi.copy(bg_buf, "101418")
opts.background = bg_buf

opts.width = 900
opts.height = 700

local ctx_ptr = ffi.new("kc_wvw_t*[1]")
local ret = wvw.kc_wvw_open(ctx_ptr, opts)
if ret ~= 0 then
    local err = wvw.kc_wvw_get_error(ctx_ptr[0])
    error("kcapp demo: failed to open window: " .. (err and ffi.string(err) or "unknown error"))
end

local window = {}
window._wvw_ctx = ctx_ptr[0]

kcapp.bridge(window, {"redp2p"})

wvw.kc_wvw_loop(ctx_ptr[0])

wvw.kc_wvw_close(ctx_ptr[0])
