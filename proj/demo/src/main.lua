-- main.lua
-- Summary: kcapp demo application entry point.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local kcapp = require("kcapp")

kcapp.window({
    url = "src/www/index.html",
    title = "Demo",
    background = "101418",
    width = 900,
    height = 700
}, {
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
