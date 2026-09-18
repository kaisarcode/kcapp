# kcapp

`kcapp` composes portable, runnable directories for LuaJIT-based desktop applications.

It does not compile C, does not rebuild kclib, does not rebuild LuaJIT, and does not require `wvw`. It collects already-built artifacts and the project's Lua source into a runnable directory for a given target.

## Usage

```sh
make PROJECT=NAME <arch>/<platform>
```

Example:

```sh
make PROJECT=demo x86_64/linux
```

Output:

```text
projects/demo/bin/x86_64/linux/
├── luajit
├── main.lua
└── lib/
    ├── libb64.cdef
    └── libb64.so
```

From the output directory:

```sh
./luajit main.lua "Hola"
```

produces:

```text
SG9sYQ==
```

## Layout

```text
kcapp/
├── AGENTS.md
├── Makefile
├── README.md
└── projects/
    └── demo/
        ├── config.json
        └── src/
            └── main.lua
```

A project contains only its own Lua source and a minimal `config.json`. Dependencies and the LuaJIT runtime are resolved automatically.

## Configuration

Each project declares the kclib dependencies it needs:

```json
{
  "kclib": ["b64"]
}
```

## Dependencies

The Makefile resolves dependencies from sibling repositories by default. Override them per invocation or environment:

```make
KCLIB_DIST_DIR ?= ../kclib/dist
LUAJIT_DIST_DIR ?= ../luajit/dist
```

For example, with the repositories together under one parent directory:

```sh
make PROJECT=demo x86_64/linux
make KCLIB_DIST_DIR=/abs/path/kclib/dist x86_64/linux
```

For dependency `NAME` and target `<arch>/<platform>`, `kcapp` selects `libNAME.cdef` and the platform shared library:

| platform | library |
| :--- | :--- |
| linux | `libNAME.so` |
| windows | `libNAME.dll` |
| macos | `libNAME.dylib` |

`kcapp` copies LuaJIT from the precompiler distribution; it never rebuilds it. If the target directory or any required artifact is missing, `kcapp` fails clearly and does not attempt to fix or rebuild the dependency.

## Targets

Valid targets come from the artifacts that actually exist, for example:

```text
x86_64/linux
x86_64/windows
x86_64/macos
aarch64/linux
aarch64/macos
```

`kcapp` is desktop-only. Android, iOS, iossim, and wasm are not supported.