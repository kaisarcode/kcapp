# AGENTS.md

## Purpose

Use this repository to develop desktop applications with kcapp.

For normal application work, stay inside `proj/<name>/`. Do not inspect or
modify kcapp runtime, launcher, generator, bridge, or build plumbing unless the
task explicitly asks to change kcapp itself.

## Creating an application

Always create a new application from the repository root with:

```sh
./scripts/init.sh <name>
```

Do not create a kcapp project manually.

The command creates:

```text
proj/<name>/
├── Makefile
├── README.md
├── config.json
└── src/
    └── main.lua
```

`src/main.lua` is the application entry point.

Develop application code, Lua modules, HTML, CSS, JavaScript, templates,
configuration, and other app-owned resources under `src/`.

Do not edit generated `bin/` output.

## Kclib dependencies

Kclibs provide native capabilities to the application.

Choose libraries from:

https://github.com/kaisarcode/kclib/blob/master/INDEX.md

For the exact behavior and public API of a library, read its project
documentation under:

```text
https://github.com/kaisarcode/kclib/tree/master/proj/NAME.c
```

Declare every kclib used by the application in `config.json`:

```json
{
  "kclib": ["http", "redp2p"]
}
```

Do not rely on undeclared kclibs.

## Using kclibs from Lua

Application Lua uses the shared kcapp scripting layer.

Start with:

```lua
local kcapp = require("kcapp")
```

Load a kclib with:

```lua
local http = kcapp.load("http")
```

Then call its scripting API directly:

```lua
local result = http.some_operation(...)
```

Use normal Lua values.

Do not write FFI bindings or call C symbols directly from application code.

Do not use `ffi.new()`, `ffi.cast()`, `ffi.string()`, `ffi.NULL`, C structs,
output pointers, explicit native counts, allocation functions, or `kc_*` symbols
in project Lua.

The kcapp runtime translates the public kclib API into natural scripting values.

Typical projections are:

```text
C public struct        -> Lua table
array + count          -> Lua array
buffer + size          -> Lua string
opaque capability      -> Lua object
out parameter          -> returned value
*_free() ownership     -> handled internally
kc_name_operation()    -> name.operation()
```

Opaque capabilities are used as Lua objects when the library exposes them:

```lua
local mdp = kcapp.load("mdp")

local document, status = mdp.open("# Hello")
if not document then
    error("mdp status " .. status)
end

print(document:html())
document:close()
```

## Visual applications

A kcapp may be headless. A WebView is optional.

For a visual application, open the window from Lua:

```lua
local kcapp = require("kcapp")

kcapp.window({
    url = "src/www/index.html",
    title = "My App",
    width = 900,
    height = 700
}, {
    "http",
    "redp2p"
})
```

The second argument is the explicit list of kclibs exposed to that WebView.

Declaring a kclib in `config.json` makes it available to the application build.
It is exposed to frontend JavaScript only when included in the window list.

## Using kclibs from JavaScript

Inside a kcapp WebView, selected kclibs are available under:

```js
window.NativeBridge.<kclib>
```

Call operations asynchronously:

```js
const version = await window.NativeBridge.redp2p.version();
```

or:

```js
const result = await window.NativeBridge.http.someOperation(...);
```

Use normal JavaScript values.

Typical projections are:

```text
C public struct        -> JavaScript object
array + count          -> JavaScript array
byte buffer            -> Uint8Array
opaque capability      -> JavaScript object
out parameter          -> resolved return value
*_free() ownership     -> handled internally
kc_name_operation()    -> NativeBridge.name.operation()
```

Do not create manual JavaScript-to-C adapters.

## Building

From the application directory:

```sh
cd proj/<name>
make
```

Build a specific target with:

```sh
make <arch>/<platform>
```

Build every available desktop target with:

```sh
make all
```

From the repository root:

```sh
./scripts/build.sh <name>
```

This enters the project and runs `make all`.

## Project README

Each application must include a `README.md` written for the end user.

Document what the application does and how to use it.

Do not fill an application README with kcapp internals, LuaJIT details, native
ABI details, generated output structure, or builder implementation.

## Application rules

When developing an application:

-  create new projects with `./scripts/init.sh <name>`;
-  work inside `proj/<name>/`;
-  put application source under `src/`;
-  declare every kclib in `config.json`;
-  use `kcapp.load("name")` from Lua;
-  use `window.NativeBridge.name` from WebView JavaScript;
-  expose only the JavaScript kclibs needed by each window;
-  do not write FFI or native bindings for ordinary kclib use;
-  do not edit generated `bin/` output;
-  do not modify kcapp plumbing unless the task explicitly concerns kcapp
  itself.

The demo under `proj/demo/` is an example, not the specification. This document
is the primary guide for ordinary application development.
