# AGENTS.md

## Kcapp

This repository is the public development repository for `kcapp`.

Read the workspace-level `AGENTS.md` first. These rules add kcapp-specific conventions.

`kcapp` is a generator/composer for LuaJIT-based desktop applications. It composes already-built artifacts. It does not compile C, does not rebuild kclib, does not rebuild LuaJIT, and does not require `wvw`.

## Main principle

Do not compile again what already exists. `kcapp` composes existing artifacts:

```text
kclib/dist/...         -> copy/select
luajit-precompiler/... -> copy/select
project Lua source     -> copy
```

No compilation is required. No dependency, framework, service, telemetry, remote API, or network access belongs in the build.

## Scope

`kcapp` is desktop-only. Do not support Android, iOS, iossim, or wasm. Do not add mobile logic.

## Repository layout

The Lua source is the product. Do not use a `repo/` / `dist/` split.

```text
kcapp/
├── AGENTS.md
├── Makefile
├── README.md
└── projects/
    └── demo/
        ├── config.json
        ├── src/
        │   └── main.lua
        └── bin/
            └── <arch>/<platform>/
```

`bin/` is generated, ephemeral, and must not be tracked. Do not create `.build/`, `dist/`, or `repo/`.

## Authoritative plan

`PLAN.md` is the project-local specification for the implementation. It takes precedence over completion history or prior notes for the current milestone. Implement only the requested milestone; do not get ahead of the task.

## Composition rules

- Resolve `<arch>/<platform>` from the target.
- Resolve kclib dependencies as `$(KCLIB_DIST_DIR)/NAME.c/<arch>/<platform>/`.
- Select `libNAME.cdef` and the platform shared library (`.so`, `.dll`, `.dylib`).
- Copy LuaJIT for the target without rebuilding it.
- If a target directory or any required artifact is missing, fail clearly. Do not attempt to fix, download, or rebuild the dependency.
- Preserve the Lua source structure. Do not transform Lua code, generate bindings, or generate wrappers.

## Structure and dependencies

Use existing project mechanisms before introducing new ones. Do not add shared runtimes, registries, daemons, or service layers. Small project-local duplication is acceptable when it keeps behavior easier to inspect.

## Tests and documentation

Use the repository's existing validation paths. Update documentation when public or operational behavior changes. Keep the README consistent with the project layout and actual behavior.