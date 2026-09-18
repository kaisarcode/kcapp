# AGENTS.md

## Kcapp

This repository is the public development repository for `kcapp`.

Read the workspace-level `AGENTS.md` first. These rules add kcapp-specific conventions.

`kcapp` is a generator/composer for LuaJIT-based desktop applications. It composes already-built artifacts from kclib and LuaJIT together with the application's Lua source.

## Main principle

Do not compile again what already exists. `kcapp` composes existing artifacts:

```text
kclib/dist/...         -> copy/select
luajit-precompiler/... -> copy/select
project Lua source     -> copy
```

Dependency artifacts are selected and copied into runnable application directories. No network access belongs in the composition process.

## Scope

`kcapp` targets desktop applications: Linux, Windows, and macOS.

## Repository layout

The Lua source is the product. Projects live directly under `proj/`.

```text
kcapp/
├── AGENTS.md
├── README.md
├── proj/
│   └── demo/
│       ├── Makefile
│       ├── config.json
│       ├── src/
│       │   └── main.lua
│       └── bin/
│           └── <arch>/<platform>/
└── dist/
```

`bin/` is project-local generated output for runnable target directories.

`dist/` contains distributable application packages.

Each project carries its own self-contained `Makefile`, and composition runs from inside the project directory with `make`, `make <arch>/<platform>`, or `make all`.

## Authoritative plan

`PLAN.md` is the project-local specification for the implementation. It takes precedence over completion history or prior notes for the current milestone. Implement only the requested milestone; do not get ahead of the task.

## Composition rules

- Resolve `<arch>/<platform>` from the target.
- Resolve kclib dependencies as `$(KCLIB_DIST_DIR)/NAME.c/<arch>/<platform>/`.
- Select `libNAME.cdef` and the platform shared library (`.so`, `.dll`, `.dylib`).
- Copy LuaJIT for the target from its prebuilt distribution.
- If a target directory or any required artifact is missing, fail clearly.
- Preserve the Lua source structure. Do not transform Lua code, generate bindings, or generate wrappers.

## Structure and dependencies

Use existing project mechanisms before introducing new ones. Keep project behavior local and easy to inspect.

## Tests and documentation

Use the repository's existing validation paths. Update documentation when public or operational behavior changes. Keep the README consistent with the project layout and actual behavior.
