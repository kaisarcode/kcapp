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

* `make` composes the native target detected from the host.
* `make <arch>/<platform>` composes one target.
* `make all` composes every target for which LuaJIT and all declared kclib dependencies exist.

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

## Scripts

Build all available targets for one project:

```sh
./scripts/build.sh demo
```

This enters:

```text
proj/demo/
```

and runs:

```sh
make all
```

Package all available project builds:

```sh
./scripts/dist.sh
```

The distribution script does not build projects. It packages build outputs that already exist under each project's `bin/` directory.

## Distribution

For each existing build target:

```text
proj/<project>/bin/<arch>/<platform>/
```

`dist.sh` creates:

```text
dist/<project>/<project>-<platform>-<arch>.zip
```

For example:

```text
proj/demo/bin/x86_64/linux/
```

becomes:

```text
dist/demo/demo-linux-x86_64.zip
```

The contents of the platform build directory are stored directly at the root of the ZIP archive.

Each package also contains:

```text
SHA256SUM.txt
```

This file stores a SHA-256 digest representing the installable build contents.

For example:

```text
demo-linux-x86_64.zip
├── luajit
├── main.lua
├── lib/
│   ├── libb64.cdef
│   └── libb64.so
└── SHA256SUM.txt
```

The same build digest is published in:

```text
dist/manifest.json
```

This allows an installed application or an external update system to compare its local `SHA256SUM.txt` with the published manifest and determine whether that build has changed.

The manifest also contains:

* `updated_at`: UTC ISO-8601 generation time.
* `timestamp`: Unix generation timestamp.
* the published package checksum for each project build.

Example:

```json
{
  "updated_at": "2026-09-18T18:10:00Z",
  "timestamp": 1789755000,
  "projects": {
    "demo": {
      "packages": {
        "demo-linux-x86_64.zip": {
          "sha256": "6c3a5d4e..."
        }
      }
    }
  }
}
```

The `sha256` stored in the manifest is the build identity stored inside the corresponding package's `SHA256SUM.txt`. It is not the checksum of the ZIP file itself.

## Layout

```text
kcapp/
├── AGENTS.md
├── README.md
├── scripts/
│   ├── build.sh
│   └── dist.sh
├── proj/
│   └── demo/
│       ├── Makefile
│       ├── config.json
│       ├── src/
│       │   └── main.lua
│       └── bin/
│           └── <arch>/<platform>/
└── dist/
    ├── manifest.json
    └── demo/
        └── demo-<platform>-<arch>.zip
```

`proj/` contains application projects. A project contains its Lua source, a minimal `config.json`, and its own self-contained `Makefile`. Dependencies and the LuaJIT runtime are resolved automatically.

`bin/` contains generated runnable build targets for a project.

`dist/` contains packaged application builds and the distribution manifest.

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

| platform | library         |
| :------- | :-------------- |
| linux    | `libNAME.so`    |
| windows  | `libNAME.dll`   |
| macos    | `libNAME.dylib` |

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
