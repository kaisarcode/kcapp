-- main.lua
-- Summary: kcapp demo application entry point.
-- Author:  KaisarCode
-- Website: https://kaisarcode.com
-- License: GNU General Public License v3.0

local kcapp = require("kcapp")

local window = kcapp.open({
    url = "src/www/index.html",
    title = "Demo",
    background = "101418",
    width = 900,
    height = 700
})

kcapp.bridge(window, {"redp2p"})
kcapp.run(window)
