## Makefile
## Summary: Composes portable runnable directories for a kcapp LuaJIT desktop app.
## Author:  KaisarCode
## Website: https://kaisarcode.com
## License: GNU GPL v3

SHELL := /bin/bash
.ONESHELL:

KCLIB_DIST_DIR ?= $(abspath $(CURDIR)/../../../kclib/dist)
LUAJIT_DIST_DIR ?= $(abspath $(CURDIR)/../../../luajit/dist)
LUAJIT_INCLUDE_DIR ?= $(abspath $(CURDIR)/../../../vendor/luajit/src)
XDG_DATA_HOME ?= $(HOME)/.local/share
OSXCROSS_ROOT ?= $(XDG_DATA_HOME)/osxcross/target
WINE ?= wine

PROJECT_DIR := $(CURDIR)
PROJECT_NAME := $(notdir $(PROJECT_DIR))
CONFIG := $(PROJECT_DIR)/config.json
README := $(PROJECT_DIR)/README.md
SRC_DIR := $(PROJECT_DIR)/src
SHARE_LUA_DIR := $(PROJECT_DIR)/../../share/lua
OUT_DIR := $(PROJECT_DIR)/bin
RUN_C := $(PROJECT_DIR)/../../share/run/run.c
RUN_INCLUDE_DIR := $(PROJECT_DIR)/../../share/run

KC_LIBS := $(if $(wildcard $(CONFIG)),$(shell awk -v key='"kclib"' '{ buf = buf " " $$0 } END { if (match(buf, key "[[:space:]]*:[[:space:]]*\\[")) { s = substr(buf, RSTART + RLENGTH); while (match(s, /"[^"]*"/)) { v = substr(s, RSTART + 1, RLENGTH - 2); print v; s = substr(s, RSTART + RLENGTH) } } }' "$(CONFIG)"),)
PLATFORM_EXT_linux := so
PLATFORM_EXT_windows := dll
PLATFORM_EXT_macos := dylib
LUAJIT_RUNTIME_linux := libluajit.so
LUAJIT_RUNTIME_windows := libluajit.dll
LUAJIT_RUNTIME_macos := libluajit.dylib
LUAJIT_TARGETS := $(sort $(foreach p,linux windows macos,$(foreach f,$(wildcard $(LUAJIT_DIST_DIR)/*/$(p)/$(LUAJIT_RUNTIME_$(p))),$(patsubst %/,%,$(patsubst $(LUAJIT_DIST_DIR)/%,%,$(dir $f))))))

define lib_available
$(if $(and $(wildcard $(KCLIB_DIST_DIR)/$(1).c/$(2)/lib$(1).h),$(wildcard $(KCLIB_DIST_DIR)/$(1).c/$(2)/lib$(1).cdef),$(wildcard $(KCLIB_DIST_DIR)/$(1).c/$(2)/lib$(1).$(PLATFORM_EXT_$(notdir $(2))))),1)
endef

KC_LIB_COUNT := $(words $(KC_LIBS))

define available_lib_count
$(words $(filter 1,$(foreach d,$(KC_LIBS),$(call lib_available,$(d),$(1)))))
endef

define all_libs_available
$(if $(filter $(KC_LIB_COUNT),$(call available_lib_count,$(1))),$(1))
endef

define target_available
$(if $(wildcard $(LUAJIT_DIST_DIR)/$(1)/$(LUAJIT_RUNTIME_$(notdir $(1)))),$(call all_libs_available,$(1)))
endef

AVAILABLE_TARGETS := $(foreach t,$(LUAJIT_TARGETS),$(if $(call target_available,$(t)),$(t)))
HOST_ARCH := $(shell uname -m)
HOST_SYSTEM := $(shell uname -s)
NATIVE_ARCH := unsupported
ifneq ($(filter x86_64 amd64,$(HOST_ARCH)),)
NATIVE_ARCH := x86_64
endif
ifneq ($(filter aarch64 arm64,$(HOST_ARCH)),)
NATIVE_ARCH := aarch64
endif
ifneq ($(filter i386 i686,$(HOST_ARCH)),)
NATIVE_ARCH := i686
endif
NATIVE_PLATFORM := unsupported
ifeq ($(HOST_SYSTEM),Linux)
NATIVE_PLATFORM := linux
endif
ifneq ($(filter MINGW% MSYS% CYGWIN%,$(HOST_SYSTEM)),)
NATIVE_PLATFORM := windows
endif
ifeq ($(HOST_SYSTEM),Darwin)
NATIVE_PLATFORM := macos
endif
NATIVE_TARGET := $(NATIVE_ARCH)/$(NATIVE_PLATFORM)
NATIVE_EXE_EXT :=
ifeq ($(NATIVE_PLATFORM),windows)
NATIVE_EXE_EXT := .exe
endif
ifeq ($(filter $(NATIVE_TARGET),$(AVAILABLE_TARGETS)),)
.DEFAULT_GOAL := help
else
.DEFAULT_GOAL := $(NATIVE_TARGET)
endif

.PHONY: all help test wine
all: $(AVAILABLE_TARGETS)
	@if [ -z '$(AVAILABLE_TARGETS)' ]; then echo "kcapp: no targets available for this project" >&2; exit 1; fi

help:
	@echo 'Usage: make [<arch>/<platform>|all|test]'

test:
	@if [ -n "$(filter wine,$(MAKECMDGOALS))" ]; then \
		if ! command -v $(WINE) >/dev/null 2>&1; then echo "Missing Wine runtime: $(WINE)" >&2; exit 1; fi; \
		if [ ! -f $(OUT_DIR)/x86_64/windows/$(PROJECT_NAME).exe ]; then echo "Missing Windows artifacts." >&2; exit 1; fi; \
		out=$$(cd $(OUT_DIR)/x86_64/windows && WINEDEBUG=-all $(WINE) $(PROJECT_NAME).exe 2>/dev/null | tr -d '\r'); \
		[ -z "$$out" ] || { echo "FAIL: expected empty Base64 output, got: $$out" >&2; exit 1; }; \
	else \
		if [ ! -f $(OUT_DIR)/$(NATIVE_TARGET)/$(PROJECT_NAME)$(NATIVE_EXE_EXT) ]; then $(MAKE) $(NATIVE_TARGET); fi; \
		[ -L $(PROJECT_DIR)/$(PROJECT_NAME)$(NATIVE_EXE_EXT) ] || { echo "FAIL: missing native launcher link" >&2; exit 1; }; \
		out=$$(cd $(PROJECT_DIR) && ./$(PROJECT_NAME)$(NATIVE_EXE_EXT)); \
		[ -z "$$out" ] || { echo "FAIL: expected empty Base64 output, got: $$out" >&2; exit 1; }; \
	fi
	@echo "OK test"

wine:
	@if [ -z "$(filter test,$(MAKECMDGOALS)) ]; then echo "Use 'make test wine' to run tests through Wine." >&2; exit 1; fi
	@:

define compose
@set -eu; \
target='$@'; \
arch='$(word 1,$(subst /, ,$@))'; \
platform='$(word 2,$(subst /, ,$@))'; \
out='$(OUT_DIR)/$@'; \
case "$$target" in \
	*/*/*|*../*) echo "kcapp: invalid target '$$target' (expected <arch>/<platform>)" >&2; exit 1 ;; \
	*/*) ;; \
	*) echo "kcapp: invalid target '$$target' (expected <arch>/<platform>)" >&2; exit 1 ;; \
esac; \
[ -f '$(CONFIG)' ] || { echo "kcapp: missing config: $(CONFIG)" >&2; exit 1; }; \
[ -f '$(SRC_DIR)/main.lua' ] || { echo "kcapp: missing source entry point: $(SRC_DIR)/main.lua" >&2; exit 1; }; \
[ -f '$(SHARE_LUA_DIR)/kcapp.lua' ] || { echo "kcapp: missing shared Lua runtime: $(SHARE_LUA_DIR)/kcapp.lua" >&2; exit 1; }; \
[ -f '$(SHARE_LUA_DIR)/bridge.lua' ] || { echo "kcapp: missing shared bridge template: $(SHARE_LUA_DIR)/bridge.lua" >&2; exit 1; }; \
[ -f '$(RUN_C)' ] || { echo "kcapp: missing launcher source: $(RUN_C)" >&2; exit 1; }; \
[ -f '$(LUAJIT_INCLUDE_DIR)/lua.h' ] || { echo "kcapp: missing LuaJIT headers: $(LUAJIT_INCLUDE_DIR)" >&2; exit 1; }; \
case "$$platform" in \
linux) lext='.so'; runtime='libluajit.so'; executable='$(PROJECT_NAME)'; \
	case "$$arch" in x86_64) compiler=cc ;; i686) compiler=i686-linux-gnu-gcc ;; aarch64) compiler=aarch64-linux-gnu-gcc ;; armv7) compiler=arm-linux-gnueabi-gcc ;; armv7hf) compiler=arm-linux-gnueabihf-gcc ;; mips) compiler=mips-linux-gnu-gcc ;; mipsel) compiler=mipsel-linux-gnu-gcc ;; mips64el) compiler=mips64el-linux-gnuabi64-gcc ;; *) echo "kcapp: unsupported Linux architecture: $$arch" >&2; exit 1 ;; esac ;; \
windows) lext='.dll'; runtime='libluajit.dll'; executable='$(PROJECT_NAME).exe'; \
	case "$$arch" in x86_64) compiler=x86_64-w64-mingw32-gcc ;; i686) compiler=i686-w64-mingw32-gcc ;; *) echo "kcapp: unsupported Windows architecture: $$arch" >&2; exit 1 ;; esac ;; \
macos) lext='.dylib'; runtime='libluajit.dylib'; executable='$(PROJECT_NAME)'; \
	case "$$arch" in x86_64) compiler='$(OSXCROSS_ROOT)/bin/o64-clang' ;; aarch64) compiler='$(OSXCROSS_ROOT)/bin/oa64-clang' ;; *) echo "kcapp: unsupported macOS architecture: $$arch" >&2; exit 1 ;; esac ;; \
*) echo "kcapp: unsupported platform '$$platform'" >&2; exit 1 ;; \
esac; \
ltarget='$(LUAJIT_DIST_DIR)/'"$$arch"'/'"$$platform"; \
[ -x "$$compiler" ] || command -v "$$compiler" >/dev/null 2>&1 || { echo "kcapp: missing compiler for $$target: $$compiler" >&2; exit 1; }; \
[ -f "$$ltarget/$$runtime" ] || { echo "kcapp: LuaJIT runtime not available for $$target: $$ltarget/$$runtime" >&2; exit 1; }; \
mkdir -p "$$out/lib" "$$out/src"; \
rm -f "$$out/luajit" "$$out/luajit.exe" "$$out/main.lua"; \
rm -rf "$$out/share"; \
cp -R '$(SRC_DIR)/.' "$$out/src/"; \
cp '$(SHARE_LUA_DIR)/kcapp.lua' "$$out/src/kcapp.lua"; \
if [ -f '$(README)' ]; then cp '$(README)' "$$out/README.md"; fi; \
\
# GENERATE BRIDGE.LUA WITH EMBEDDED METADATA
luajit "$(SHARE_LUA_DIR)/bridge.lua" --materialize "$(KCLIB_DIST_DIR)" "$(word 1,$(subst /, ,$@))" "$(word 2,$(subst /, ,$@))" "$(OUT_DIR)/$@/src/bridge.lua" $(KC_LIBS); \
\
case "$$platform" in \
linux) cp "$$ltarget/$$runtime" "$$out/lib/"; ln -sf "$$runtime" "$$out/lib/libluajit-5.1.so.2"; "$$compiler" -std=c11 -I'$(LUAJIT_INCLUDE_DIR)' -I'$(RUN_INCLUDE_DIR)' '$(RUN_C)' -L"$$ltarget" -Wl,-rpath,'$$ORIGIN/lib' -lluajit -o "$$out/$$executable" ;; \
windows) [ -f "$$ltarget/libluajit.dll.a" ] || { echo "kcapp: missing LuaJIT linker artifact for $$target" >&2; exit 1; }; cp "$$ltarget/$$runtime" "$$out/"; "$$compiler" -std=c11 -I'$(LUAJIT_INCLUDE_DIR)' -I'$(RUN_INCLUDE_DIR)' '$(RUN_C)' "$$ltarget/libluajit.dll.a" -o "$$out/$$executable" ;; \
macos) cp "$$ltarget/$$runtime" "$$out/"; "$$compiler" -std=c11 -I'$(LUAJIT_INCLUDE_DIR)' -I'$(RUN_INCLUDE_DIR)' '$(RUN_C)' -L"$$ltarget" -Wl,-rpath,@loader_path -lluajit -o "$$out/$$executable" ;; \
esac; \
for dep in $(KC_LIBS); do \
 	ddir='$(KCLIB_DIST_DIR)/'"$$dep"'.c/'"$$arch"'/'"$$platform"; \
 	cdef="$$ddir/lib$$dep.cdef"; lib="$$ddir/lib$$dep$$lext"; \
 	[ -f "$$cdef" ] || { echo "kcapp: missing cdef for $$dep: $$cdef" >&2; exit 1; }; \
 	[ -f "$$lib" ] || { echo "kcapp: missing shared library for $$dep: $$lib" >&2; exit 1; }; \
 	cp "$$cdef" "$$lib" "$$out/lib/"; \
 done; \
if [ "$$target" = "$(NATIVE_TARGET)" ]; then \
	link='$(PROJECT_DIR)/'"$$executable"; \
	if [ -e "$$link" ] && [ ! -L "$$link" ]; then echo "kcapp: native launcher path already exists: $$link" >&2; exit 1; fi; \
	ln -sfn "bin/$$target/$$executable" "$$link"; \
fi; \
echo "OK $$target"
endef

%:
	$(call compose)
