## Makefile
## Summary: Composes portable runnable directories for the demo LuaJIT desktop app.
## Author:  KaisarCode
## Website: https://kaisarcode.com
## License: GNU GPL v3

KCLIB_DIST_DIR ?= $(abspath $(CURDIR)/../../../kclib/dist)
LUAJIT_DIST_DIR ?= $(abspath $(CURDIR)/../../../luajit/dist)
LUAJIT_INCLUDE_DIR ?= $(abspath $(CURDIR)/../../../vendor/luajit/src)
XDG_DATA_HOME ?= $(HOME)/.local/share
OSXCROSS_ROOT ?= $(XDG_DATA_HOME)/osxcross/target

WINE ?= wine

PROJECT_DIR := $(CURDIR)
CONFIG := $(PROJECT_DIR)/config.json
README := $(PROJECT_DIR)/README.md
SRC_DIR := $(PROJECT_DIR)/src
SHARE_LUA_DIR := $(PROJECT_DIR)/../../share/lua
OUT_DIR := $(PROJECT_DIR)/bin
RUN_C := $(PROJECT_DIR)/../../share/run/run.c
RUN_INCLUDE_DIR := $(PROJECT_DIR)/../../share/run

KC_LIBS := $(if $(wildcard $(CONFIG)),$(shell awk -v key='"kclib"' '{ buf = buf " " $$0 } END { if (match(buf, key "[[:space:]]*:[[:space:]]*\\[")) { s = substr(buf, RSTART + RLENGTH); while (match(s, /"[^"]*"/)) { v = substr(s, RSTART + 1, RLENGTH - 2); print v; s = substr(s, RSTART + RLENGTH) } } }' "$(CONFIG)"),)

PLATFORM_EXT_linux   := so
PLATFORM_EXT_windows := dll
PLATFORM_EXT_macos   := dylib

LUAJIT_RUNTIME_linux := libluajit.so
LUAJIT_RUNTIME_windows := libluajit.dll
LUAJIT_RUNTIME_macos := libluajit.dylib

LUAJIT_TARGETS := $(sort $(foreach p,linux windows macos,$(foreach f,$(wildcard $(LUAJIT_DIST_DIR)/*/$(p)/$(LUAJIT_RUNTIME_$(p))),$(patsubst %/,%,$(patsubst $(LUAJIT_DIST_DIR)/%,%,$(dir $f))))))

define target_available
$(if $(wildcard $(LUAJIT_DIST_DIR)/$(1)/$(LUAJIT_RUNTIME_$(notdir $(1)))),$(if $(foreach d,$(KC_LIBS),$(and $(wildcard $(KCLIB_DIST_DIR)/$(d).c/$(1)/lib$(d).cdef),$(wildcard $(KCLIB_DIST_DIR)/$(d).c/$(1)/lib$(d).$(PLATFORM_EXT_$(notdir $(1)))))),$(1)))
endef

AVAILABLE_TARGETS := $(foreach t,$(LUAJIT_TARGETS),$(if $(call target_available,$(t)),$(t)))

HOST_ARCH     := $(shell uname -m)
HOST_SYSTEM   := $(shell uname -s)

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
	@if [ -z '$(AVAILABLE_TARGETS)' ]; then \
		echo "kcapp: no targets available for this project" >&2; \
		exit 1; \
	fi

help:
	@echo 'Usage:'
	@echo '  make                 # compose the native target'
	@echo '  make <arch>/<platform>'
	@echo '  make all             # compose every available desktop target'
	@echo '  make test            # run the native test'
	@echo '  make test wine       # run the test under Wine'
	@echo 'Example:'
	@echo '  make x86_64/linux'
	@echo 'Output:'
	@echo '  bin/<arch>/<platform>/'

test:
	@if [ -n "$(filter wine,$(MAKECMDGOALS))" ]; then \
		if ! command -v $(WINE) >/dev/null 2>&1; then \
			echo "Missing Wine runtime: $(WINE)" >&2; \
			exit 1; \
		fi; \
		if [ ! -f $(OUT_DIR)/x86_64/windows/demo.exe ]; then \
			echo "Missing Windows artifacts. Run 'make x86_64/windows' or 'make all' first." >&2; \
			exit 1; \
		fi; \
		out=$$(cd $(OUT_DIR)/x86_64/windows && WINEDEBUG=-all $(WINE) demo.exe "Hello" 2>/dev/null | tr -d '\r'); \
		[ "$$out" = "SGVsbG8=" ] || { echo "FAIL: expected SGVsbG8=, got: $$out" >&2; exit 1; }; \
	else \
		if [ "$(NATIVE_ARCH)" = "unsupported" ] || [ "$(NATIVE_PLATFORM)" = "unsupported" ]; then \
			echo "Unsupported native test target $(HOST_ARCH)/$(HOST_SYSTEM)" >&2; \
			exit 1; \
		fi; \
		if [ ! -f $(OUT_DIR)/$(NATIVE_TARGET)/demo$(NATIVE_EXE_EXT) ]; then \
			$(MAKE) $(NATIVE_TARGET); \
		fi; \
		[ -L $(PROJECT_DIR)/demo$(NATIVE_EXE_EXT) ] || { echo "FAIL: missing native launcher link" >&2; exit 1; }; \
		out=$$(cd $(PROJECT_DIR) && ./demo$(NATIVE_EXE_EXT) "Hello"); \
		[ "$$out" = "SGVsbG8=" ] || { echo "FAIL: expected SGVsbG8=, got: $$out" >&2; exit 1; }; \
		out_dir=$$(cd $(OUT_DIR)/$(NATIVE_TARGET) && pwd); \
		out=$$(cd /tmp && "$$out_dir/demo$(NATIVE_EXE_EXT)" "World"); \
		[ "$$out" = "V29ybGQ=" ] || { echo "FAIL: expected V29ybGQ=, got: $$out" >&2; exit 1; }; \
		[ -f "$$out_dir/src/main.lua" ] || { echo "FAIL: missing src/main.lua" >&2; exit 1; }; \
		[ -d "$$out_dir/src" ] || { echo "FAIL: missing source tree" >&2; exit 1; }; \
		[ -f "$$out_dir/share/lua/kcapp.lua" ] || { echo "FAIL: missing shared Lua runtime" >&2; exit 1; }; \
		if find "$$out_dir" -maxdepth 1 -type f \( -name luajit -o -name luajit.exe \) | grep -q .; then \
			echo "FAIL: standalone LuaJIT executable was packaged" >&2; exit 1; \
		fi; \
	fi
	@echo "OK test"

wine:
	@if [ -z "$(filter test,$(MAKECMDGOALS))" ]; then \
		echo "Use 'make test wine' to run tests through Wine." >&2; \
		exit 1; \
	fi
	@:

define compose
@set -eu; \
target='$@'; \
case "$$target" in \
	*/*/*|*../*) echo "kcapp: invalid target '$$target' (expected <arch>/<platform>)" >&2; exit 1 ;; \
	*/*) ;; \
	*) echo "kcapp: invalid target '$$target' (expected <arch>/<platform>)" >&2; exit 1 ;; \
esac; \
	arch="$${target%%/*}"; \
	platform="$${target##*/}"; \
	[ -f '$(CONFIG)' ] || { echo "kcapp: missing config: $(CONFIG)" >&2; exit 1; }; \
	[ -f '$(SRC_DIR)/main.lua' ] || { echo "kcapp: missing source entry point: $(SRC_DIR)/main.lua" >&2; exit 1; }; \
	[ -f '$(SHARE_LUA_DIR)/kcapp.lua' ] || { echo "kcapp: missing shared Lua runtime: $(SHARE_LUA_DIR)/kcapp.lua" >&2; exit 1; }; \
	[ -f '$(RUN_C)' ] || { echo "kcapp: missing launcher source: $(RUN_C)" >&2; exit 1; }; \
	[ -f '$(LUAJIT_INCLUDE_DIR)/lua.h' ] || { echo "kcapp: missing LuaJIT headers: $(LUAJIT_INCLUDE_DIR)" >&2; exit 1; }; \
	[ -n '$(KC_LIBS)' ] || { echo "kcapp: no kclib entries in $(CONFIG)" >&2; exit 1; }; \
	case "$$platform" in \
	linux)   lext='.so'; runtime='libluajit.so'; executable='$(notdir $(PROJECT_DIR))'; \
		case "$$arch" in \
			x86_64) compiler=cc ;; i686) compiler=i686-linux-gnu-gcc ;; \
			aarch64) compiler=aarch64-linux-gnu-gcc ;; armv7) compiler=arm-linux-gnueabi-gcc ;; \
			armv7hf) compiler=arm-linux-gnueabihf-gcc ;; mips) compiler=mips-linux-gnu-gcc ;; \
			mipsel) compiler=mipsel-linux-gnu-gcc ;; mips64el) compiler=mips64el-linux-gnuabi64-gcc ;; \
			*) echo "kcapp: unsupported Linux architecture: $$arch" >&2; exit 1 ;; \
		esac ;; \
	windows) lext='.dll'; runtime='libluajit.dll'; executable='$(notdir $(PROJECT_DIR)).exe'; \
		case "$$arch" in x86_64) compiler=x86_64-w64-mingw32-gcc ;; i686) compiler=i686-w64-mingw32-gcc ;; *) echo "kcapp: unsupported Windows architecture: $$arch" >&2; exit 1 ;; esac ;; \
	macos)   lext='.dylib'; runtime='libluajit.dylib'; executable='$(notdir $(PROJECT_DIR))'; \
		case "$$arch" in x86_64) compiler='$(OSXCROSS_ROOT)/bin/o64-clang' ;; aarch64) compiler='$(OSXCROSS_ROOT)/bin/oa64-clang' ;; *) echo "kcapp: unsupported macOS architecture: $$arch" >&2; exit 1 ;; esac ;; \
	*) echo "kcapp: unsupported platform '$$platform'" >&2; exit 1 ;; \
	esac; \
	ltarget='$(LUAJIT_DIST_DIR)/'"$$arch"'/'"$$platform"; \
	[ -x "$$compiler" ] || command -v "$$compiler" >/dev/null 2>&1 || { echo "kcapp: missing compiler for $$target: $$compiler" >&2; exit 1; }; \
	[ -f "$$ltarget/$$runtime" ] || { echo "kcapp: LuaJIT runtime not available for $$target: $$ltarget/$$runtime" >&2; exit 1; }; \
	out='$(OUT_DIR)/'"$$target"; \
	mkdir -p "$$out/lib"; \
	rm -f "$$out/luajit" "$$out/luajit.exe" "$$out/main.lua"; \
	mkdir -p "$$out/src"; \
	cp -R '$(SRC_DIR)/.' "$$out/src/"; \
	mkdir -p "$$out/share/lua"; \
	cp -R '$(SHARE_LUA_DIR)/.' "$$out/share/lua/"; \
	if [ -f '$(README)' ]; then cp '$(README)' "$$out/README.md"; fi; \
	case "$$platform" in \
	linux)   cp "$$ltarget/$$runtime" "$$out/lib/"; ln -sf "$$runtime" "$$out/lib/libluajit-5.1.so.2"; "$$compiler" -std=c11 -I'$(LUAJIT_INCLUDE_DIR)' -I'$(RUN_INCLUDE_DIR)' '$(RUN_C)' -L"$$ltarget" -Wl,-rpath,'$$ORIGIN/lib' -lluajit -o "$$out/$$executable" ;; \
	windows) [ -f "$$ltarget/libluajit.dll.a" ] || { echo "kcapp: missing LuaJIT linker artifact for $$target" >&2; exit 1; }; cp "$$ltarget/$$runtime" "$$out/"; "$$compiler" -std=c11 -I'$(LUAJIT_INCLUDE_DIR)' -I'$(RUN_INCLUDE_DIR)' '$(RUN_C)' "$$ltarget/libluajit.dll.a" -o "$$out/$$executable" ;; \
	macos)   cp "$$ltarget/$$runtime" "$$out/"; "$$compiler" -std=c11 -I'$(LUAJIT_INCLUDE_DIR)' -I'$(RUN_INCLUDE_DIR)' '$(RUN_C)' -L"$$ltarget" -Wl,-rpath,@loader_path -lluajit -o "$$out/$$executable" ;; \
	esac; \
for dep in $(KC_LIBS); do \
	ddir='$(KCLIB_DIST_DIR)/'"$$dep"'.c/'"$$arch"'/'"$$platform"; \
	cdef="$$ddir/lib$$dep.cdef"; \
	lib="$$ddir/lib$$dep$$lext"; \
	[ -f "$$cdef" ] || { echo "kcapp: missing cdef for $$dep at $$target: $$cdef" >&2; exit 1; }; \
	[ -f "$$lib" ] || { echo "kcapp: missing library for $$dep at $$target: $$lib" >&2; exit 1; }; \
	cp "$$cdef" "$$out/lib/"; \
	cp "$$lib" "$$out/lib/"; \
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
