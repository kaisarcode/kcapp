# kcapp

`kcapp` composes portable, runnable directories for LuaJIT-based desktop applications.

## Usage

From the project directory:

```sh
make                         # native target
make <arch>/<platform>       # specific target
make all                     # every available desktop target
make test                    # run the native test
make test wine               # run the test under Wine
```

Example:

```sh
cd proj/demo
make
make x86_64/linux
make all
```

- `make` composes the native target (detected from the host).
- `make <arch>/<platform>` composes one target.
- `make all` composes every target for which LuaJIT and all declared kclib dependencies exist.

Output:

```text
proj/demo/bin/x86_64/linux/
├── luajit
├── main.lua
└── lib/
    ├── libb64.cdef
    └── libb64.so
```

From the output directory:

```sh
./luajit main.lua "Hello"
```

produces:

```text
SGVsbG8=
```

## Layout

```text
kcapp/
├── AGENTS.md
├── README.md
├── proj/
│   └── demo/
│       ├── Makefile
│       ├── config.json
│       └── src/
│           └── main.lua
└── dist/
```

`proj/` contains application projects. A project contains its Lua source, a minimal `config.json`, and its own self-contained `Makefile`. Dependencies and the LuaJIT runtime are resolved automatically.

`dist/` is reserved for distributable application packages.

## Configuration

Each project declares the kclib dependencies it needs:

```json
{
  "kclib": ["b64"]
}
```

## Dependencies

The project's `Makefile` resolves dependencies from sibling repositories by default, relative to the project directory:

```make
KCLIB_DIST_DIR ?= ../../../kclib/dist
LUAJIT_DIST_DIR ?= ../../../luajit/dist
```

With the repositories together under one parent directory, a bare `make` works. To pick a different dependency location:

```sh
make KCLIB_DIST_DIR=/abs/path/kclib/dist x86_64/linux
```

For dependency `NAME` and target `<arch>/<platform>`, `kcapp` selects `libNAME.cdef` and the platform shared library:

| platform | library |
| :--- | :--- |
| linux | `libNAME.so` |
| windows | `libNAME.dll` |
| macos | `libNAME.dylib` |

`kcapp` copies LuaJIT from the precompiler distribution. If the target directory or any required artifact is missing, composition fails with a clear error.

## Targets

Valid targets come from the artifacts that actually exist, for example:

```text
x86_64/linux
x86_64/windows
x86_64/macos
aarch64/linux
aarch64/macos
```

`kcapp` targets desktop platforms: Linux, Windows, and macOS.
