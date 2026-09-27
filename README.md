# kcapp

`kcapp` is a small desktop application environment built around Lua and optional WebView frontends.

Applications live under `proj/`, use Lua as their main runtime, and can consume native capabilities from kclib without writing native bindings.

## Create an application

From the repository root:

```sh
./scripts/init.sh myapp
```

This creates:

```text
proj/myapp/
├── Makefile
├── README.md
├── config.json
└── src/
    └── main.lua
```

`src/main.lua` is the application entry point.

Put the rest of the application under `src/`: Lua modules, HTML, CSS, JavaScript, templates, configuration, images, and other resources.

## Hello world

A minimal application can be entirely Lua:

```lua
local kcapp = require("kcapp")

print("Hello from kcapp")
```

Build it from the project directory:

```sh
cd proj/myapp
make
```

Then run the generated application from its target directory.

## Using kclibs

Kclibs provide reusable native capabilities such as HTTP handling, networking, templates, Markdown, storage, WebView, tray integration, local AI, and more.

Browse the catalog here:

https://github.com/kaisarcode/kclib/blob/master/INDEX.md

Declare every library your application uses in `config.json`:

```json
{
  "kclib": ["http", "mdp"]
}
```

Load a declared library from Lua:

```lua
local kcapp = require("kcapp")
local mdp = kcapp.load("mdp")

local document, status = mdp.open("# Hello")

if not document then
    error("mdp status " .. status)
end

print(document:html())
document:close()
```

The Lua API uses normal scripting values and objects. Application code does not need to deal with native pointers, C structs, allocation functions, or FFI details.

For the exact operations offered by a library, read its README under:

```text
kclib/proj/NAME.c/README.md
```

## Visual applications

A kcapp does not need a GUI, but a visual application can open a WebView from Lua.

Example:

```lua
local kcapp = require("kcapp")

kcapp.window({
    url = "src/www/index.html",
    title = "My App",
    width = 900,
    height = 700
}, {
    "http",
    "mdp"
})
```

The first argument configures the window.

The second argument lists the kclibs that frontend JavaScript is allowed to use.

A typical project may look like:

```text
proj/myapp/
├── Makefile
├── README.md
├── config.json
└── src/
    ├── main.lua
    └── www/
        ├── index.html
        ├── css/
        │   └── app.css
        └── js/
            └── app.js
```

## Using kclibs from JavaScript

Kclibs exposed by the window are available under:

```js
window.NativeBridge.<name>
```

For example:

```js
const version = await window.NativeBridge.http.version();
```

Operations return ordinary JavaScript values.

Example:

```js
const bytes = await window.NativeBridge.http.request({
    method: "GET",
    target: "/",
    headers: [],
    body: new Uint8Array(),
    chunked: 0
});
```

Native capabilities that represent persistent objects are exposed as JavaScript objects with methods.

## Build commands

From a project directory:

```sh
make
```

Build one specific target:

```sh
make <arch>/<platform>
```

For example:

```sh
make x86_64/linux
```

Build every available desktop target:

```sh
make all
```

From the repository root:

```sh
./scripts/build.sh myapp
```

This builds all available targets for that project.

Generated builds are written under:

```text
proj/myapp/bin/<arch>/<platform>/
```

Do not edit generated build output.

## Package applications

After building projects, create distributable packages with:

```sh
./scripts/dist.sh
```

Packages are written under:

```text
dist/<project>/
```

The distribution step packages existing builds; it does not build the application for you.

## Project configuration

The main application configuration file is:

```text
proj/<name>/config.json
```

At minimum it declares the kclibs used by the application:

```json
{
  "kclib": []
}
```

Add only the libraries the application actually needs.

## Project README

Each application has its own `README.md`.

Write it for the people using the application. Describe what the app does, how to start it, important features, user-visible files or permissions, and relevant limitations.

Development details about kcapp itself do not belong in an application README.

## Example

`proj/demo/` contains a complete example showing Lua, a WebView frontend, and kclib calls from JavaScript.

Use it as a reference when you need a working example.
