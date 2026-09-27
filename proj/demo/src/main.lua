-- main.lua
-- Summary: kcapp demo application entry point.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local kcapp = require("kcapp")
local wvw = kcapp.load("wvw")

local window, status = wvw.open({
    url = "src/www/index.html",
    title = "Demo",
    background = "101418",
    width = 900,
    height = 700
})

if not window then
    error("wvw status " .. tostring(status))
end

kcapp.bridge(window, {
    "b64",
    "demo",
    "dmn",
    "emb",
    "flow",
    "hnsw",
    "http",
    "init",
    "lng",
    "mdp",
    "min",
    "mmap",
    "netl",
    "nets",
    "ngram",
    "redp2p",
    "tpl",
    "tpm",
    "tray",
    "trust",
    "wch"
})
