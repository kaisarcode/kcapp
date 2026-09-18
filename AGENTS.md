# AGENTS.md

## Kcapp

This repository is the public development repository for `kcapp`.

Read the workspace-level `AGENTS.md` first. These rules add kcapp-specific conventions.

`kcapp` is a generator/composer for LuaJIT-based desktop applications. It composes already-built artifacts from kclib and LuaJIT together with the application's Lua source.

Each composed application exposes its own project-named native executable. The launcher resolves its real executable location, changes to its application root, and runs `src/main.lua` from there. Invoking it through a symlink does not change that root.

`share/lua/kcapp.lua` is the shared Lua runtime module for all applications. Project Lua code must use `require("kcapp")` instead of duplicating shared kclib-loading helpers.

## Main principle

Do not compile again what already exists. `kcapp` composes existing artifacts:

```text
kclib/dist/...         -> copy/select
luajit-precompiler/... -> copy/select
project Lua source     -> copy
```

Dependency artifacts are selected and copied into runnable application directories. LuaJIT is linked as a prebuilt shared library; its standalone executable is not an end-user runtime component. No network access belongs in the composition process.

## Scope

`kcapp` targets desktop applications: Linux, Windows, and macOS.

## Repository layout

The Lua source is the product. Projects live directly under `proj/`.

```text
kcapp/
├── AGENTS.md
├── README.md
├── scripts/
│   ├── init.sh
│   ├── build.sh
│   └── dist.sh
├── share/
│   ├── init/
│   │   └── Makefile
│   ├── lua/
│   │   └── kcapp.lua
│   └── run/
│       ├── run.c
│       └── run.h
├── proj/
│   └── demo/
│       ├── README.md
│       ├── Makefile
│       ├── config.json
│       ├── src/
│       │   └── main.lua
│       └── bin/
│           └── <arch>/<platform>/
└── dist/
    ├── manifest.json
    └── <project>/
        └── <project>-<platform>-<arch>.zip
```

`bin/` is project-local generated output for runnable target directories.

Generated applications include the shared Lua runtime under `share/lua/`. The launcher prepends `share/lua` and `src` module paths to Lua's `package.path`, while retaining the existing path entries.

`dist/` contains distributable application packages.

Each project carries its own self-contained `Makefile`, and composition runs from inside the project directory with `make`, `make <arch>/<platform>`, or `make all`.

## Base application structure

Every kcapp project under `proj/` starts from the same minimal source structure:

```text
proj/<project>/
├── Makefile
├── README.md
├── config.json
└── src/
    └── main.lua
```

This is the canonical base project structure created by:

```sh
./scripts/init.sh <project>
```

`src/main.lua` is the mandatory application entry point.

The complete `src/` directory belongs to the application and may contain additional Lua modules, assets, configuration, templates, or other project-specific resources. Its internal structure must be preserved in generated builds and distributions.

`config.json` declares project configuration. New projects start with no kclib dependencies:

```json
{
  "kclib": []
}
```

`README.md` is end-user documentation for the application.

`Makefile` owns project build behavior and is created from the authoritative shared project template:

```text
share/init/Makefile
```

Do not maintain a second independent initial project Makefile implementation in `scripts/init.sh`.

Generated directories such as `bin/` are not part of the initial project skeleton and are created only by the build.

A generated kcapp has the conceptual runtime layout:

```text
bin/<arch>/<platform>/
├── <project>
├── README.md
├── src/
│   └── main.lua
├── share/
│   └── lua/
│       └── kcapp.lua
└── lib/
    └── ...
```

On Windows the executable is `<project>.exe`, and runtime DLL placement may differ where required by the native loader.

The application executable always treats its own real executable directory as the application root and executes:

```text
src/main.lua
```

Shared kcapp Lua functionality comes from:

```text
share/lua/kcapp.lua
```

Project source must use:

```lua
local kcapp = require("kcapp")
```

rather than copying shared kcapp helpers into individual projects.

## Project initialization

`scripts/init.sh <project>` creates a new kcapp project using the canonical base application structure.

It creates only:

```text
proj/<project>/
├── Makefile
├── README.md
├── config.json
└── src/
    └── main.lua
```

It does not:

* create `bin/`;
* create or modify `dist/`;
* run `make`;
* add kclib dependencies;
* copy shared runtime source into the project;
* modify an existing project.

If `proj/<project>` already exists in any form, initialization must stop with a clear diagnostic and leave the existing path untouched.

Do not merge, repair, overwrite, regenerate, or complete existing projects through `init.sh`.

New projects start with:

```json
{
  "kclib": []
}
```

The generated `src/main.lua` may use `require("kcapp")`, but shared runtime files remain authoritative under `share/` and are copied only into generated build output.

## Build scripts

`scripts/build.sh <project>` enters `proj/<project>/` and runs:

```sh
make all
```

The build script delegates build behavior to the project's own `Makefile`. Do not duplicate project build logic in `scripts/build.sh`.

## Distribution

`scripts/dist.sh` packages existing project build outputs. It does not build projects.

Each existing target under:

```text
proj/<project>/bin/<arch>/<platform>/
```

is packaged as:

```text
dist/<project>/<project>-<platform>-<arch>.zip
```

The contents of `<platform>/` are stored directly at the root of the ZIP archive.

Each package contains:

```text
SHA256SUM.txt
```

`SHA256SUM.txt` stores one SHA-256 digest representing the installable build contents. The checksum marker itself is excluded when calculating that digest.

The same build digest is published for the package in:

```text
dist/manifest.json
```

This digest is the installed-build identity used by external systems to determine whether an installed project differs from the published build.

Shared Lua runtime files participate in this identity because they are included in every generated application directory.

Do not derive this published build identity from ZIP metadata or from the ZIP file itself. Repacking identical installable contents must not change the build identity.

`manifest.json` also contains:

* `updated_at`: UTC ISO-8601 generation time.
* `timestamp`: Unix generation timestamp.
* `projects`: published projects and their package build digests.

Packaging and distribution metadata generation belong in `scripts/dist.sh`. Do not move project compilation into the distribution step.

## Project READMEs

Every project under `proj/` must include a `README.md`.

Project READMEs are end-user documentation. Unlike kclib documentation, they are written for people who want to use the application, not for developers who want to build or integrate it.

Write project documentation in clear, non-technical language.

A project README should explain, when applicable:

* what the application does;
* who it is useful for;
* how to start and use it;
* the main user-facing features;
* any files, folders, permissions, or system requirements the user must know about;
* platform-specific usage differences that affect the user;
* where the application stores or reads user-visible data;
* limitations or important behavior a user should know before using it.

Do not document internal implementation details unless they directly affect normal use.

Avoid developer-oriented material such as build instructions, compiler details, internal dependency layout, LuaJIT internals, kclib integration, source architecture, or generated artifact structure in a project README.

Repository-level developer and distribution documentation belongs in the root `README.md`, `AGENTS.md`, project `Makefile`, or other development documentation.

Keep each project README specific to the actual application. Do not use a generic template mechanically when the application needs different user guidance.

## Authoritative plan

`PLAN.md` is the project-local specification for the implementation. It takes precedence over completion history or prior notes for the current milestone. Implement only the requested milestone; do not get ahead of the task.

## Composition rules

* Resolve `<arch>/<platform>` from the target.
* Resolve kclib dependencies as `$(KCLIB_DIST_DIR)/NAME.c/<arch>/<platform>/`.
* Select `libNAME.cdef` and the platform shared library (`.so`, `.dll`, `.dylib`).
* Compile the shared launcher against the target's prebuilt LuaJIT shared library and copy only the required LuaJIT runtime library.
* Do not copy the standalone `luajit` or `luajit.exe` executable into application output.
* If a target directory or any required artifact is missing, fail clearly.
* Preserve the complete `src/` tree, including nested modules, assets, and configuration.
* Do not transform Lua code, generate bindings, or generate wrappers.
* Copy the shared Lua runtime to `share/lua/` in generated applications without copying it into project source trees.
* The launcher must resolve the real executable location before deriving the application root, including when invoked through a symlink.
* The launcher must expose `share/lua` and `src` through Lua's `package.path`.
* The launcher must execute `src/main.lua` relative to the application root.

## Structure and dependencies

Use existing project mechanisms before introducing new ones. Keep project behavior local and easy to inspect.

Shared implementation belongs under `share/` only when it represents behavior genuinely common to kcapps.

Do not duplicate shared launcher code, shared Lua runtime code, or the initial project Makefile implementation across individual projects.

## Tests and documentation

Use the repository's existing validation paths. Update documentation when public or operational behavior changes. Keep the root README consistent with the repository layout and actual behavior.

Keep each project README focused on the end-user experience of that application.
