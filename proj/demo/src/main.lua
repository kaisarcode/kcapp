local ffi = require("ffi");

local function load(name)
    local def = io.open("./lib/lib"..name..".cdef", "r");
    ffi.cdef(def:read("*a")); def:close();
    local ext = ".so";
    if (ffi.os == "Windows") then ext = ".dll";
    elseif (ffi.os == "OSX") then ext = ".dylib";
    end
    return ffi.load("./lib/lib"..name..ext);
end

local b64 = {};
local libb64 = load("b64");

function b64.encode(str)
    local val = libb64.kc_b64_encode(str, #str);
    if val == nil then return nil; end
    return ffi.string(val);
end

function b64.decode(str)
    local siz = ffi.new("size_t[1]");
    local val = libb64.kc_b64_decode(str, siz);
    if val == nil then return nil; end
    return ffi.string(val, siz[0]);
end

local input = "";
if (arg[1] ~= nil) then
    input = arg[1];
end

print(b64.encode(input));

