## Makefile
## Summary: Composes portable runnable directories for the demo LuaJIT desktop app.
## Author:  KaisarCode
## Website: https://kaisarcode.com
## License: GNU GPL v3

KCLIB_DIST_DIR ?= $(abspath $(CURDIR)/../../../kclib/dist)
LUAJIT_DIST_DIR ?= $(abspath $(CURDIR)/../../../luajit/dist)

WINE ?= wine

PROJECT_DIR := $(CURDIR)
CONFIG := $(PROJECT_DIR)/config.json
SRC_DIR := $(PROJECT_DIR)/src
OUT_DIR := $(PROJECT_DIR)/bin

KC_LIBS := $(if $(wildcard $(CONFIG)),$(shell awk -v key='"kclib"' '{ buf = buf " " $$0 } END { if (match(buf, key "[[:space:]]*:[[:space:]]*\\[")) { s = substr(buf, RSTART + RLENGTH); while (match(s, /"[^"]*"/)) { v = substr(s, RSTART + 1, RLENGTH - 2); print v; s = substr(s, RSTART + RLENGTH) } } }' "$(CONFIG)"),)

PLATFORM_EXT_linux   := so
PLATFORM_EXT_windows := dll
PLATFORM_EXT_macos   := dylib

LUAJIT_TARGETS := $(sort $(foreach p,linux windows macos,$(foreach f,$(wildcard $(LUAJIT_DIST_DIR)/*/$(p)/luajit*),$(patsubst %/,%,$(patsubst $(LUAJIT_DIST_DIR)/%,%,$(dir $f))))))

define target_available
$(if $(wildcard $(LUAJIT_DIST_DIR)/$(1)/luajit*),$(if $(foreach d,$(KC_LIBS),$(and $(wildcard $(KCLIB_DIST_DIR)/$(d).c/$(1)/lib$(d).cdef),$(wildcard $(KCLIB_DIST_DIR)/$(d).c/$(1)/lib$(d).$(PLATFORM_EXT_$(notdir $(1)))))),$(1)))
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
		if [ ! -f $(OUT_DIR)/x86_64/windows/luajit.exe ]; then \
			echo "Missing Windows artifacts. Run 'make x86_64/windows' or 'make all' first." >&2; \
			exit 1; \
		fi; \
		out=$$(cd $(OUT_DIR)/x86_64/windows && WINEDEBUG=-all $(WINE) luajit.exe main.lua "Hello" 2>/dev/null | tr -d '\r'); \
		[ "$$out" = "SGVsbG8=" ] || { echo "FAIL: expected SGVsbG8=, got: $$out" >&2; exit 1; }; \
	else \
		if [ "$(NATIVE_ARCH)" = "unsupported" ] || [ "$(NATIVE_PLATFORM)" = "unsupported" ]; then \
			echo "Unsupported native test target $(HOST_ARCH)/$(HOST_SYSTEM)" >&2; \
			exit 1; \
		fi; \
		if [ ! -f $(OUT_DIR)/$(NATIVE_TARGET)/luajit$(NATIVE_EXE_EXT) ]; then \
			$(MAKE) $(NATIVE_TARGET); \
		fi; \
		out=$$(cd $(OUT_DIR)/$(NATIVE_TARGET) && ./luajit$(NATIVE_EXE_EXT) main.lua "Hello"); \
		[ "$$out" = "SGVsbG8=" ] || { echo "FAIL: expected SGVsbG8=, got: $$out" >&2; exit 1; }; \
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
[ -d '$(SRC_DIR)' ] || { echo "kcapp: missing source directory: $(SRC_DIR)" >&2; exit 1; }; \
[ -n '$(KC_LIBS)' ] || { echo "kcapp: no kclib entries in $(CONFIG)" >&2; exit 1; }; \
case "$$platform" in \
	linux)   lexec='luajit';     lext='.so'    ;; \
	windows) lexec='luajit.exe'; lext='.dll'   ;; \
	macos)   lexec='luajit';     lext='.dylib' ;; \
	*) echo "kcapp: unsupported platform '$$platform'" >&2; exit 1 ;; \
esac; \
ltarget='$(LUAJIT_DIST_DIR)/'"$$arch"'/'"$$platform"; \
[ -f "$$ltarget/$$lexec" ] || { echo "kcapp: LuaJIT not available for $$target: $$ltarget/$$lexec" >&2; exit 1; }; \
out='$(OUT_DIR)/'"$$target"; \
mkdir -p "$$out/lib"; \
cp -R '$(SRC_DIR)/.' "$$out/"; \
cp "$$ltarget/$$lexec" "$$out/$$lexec"; \
chmod +x "$$out/$$lexec"; \
case "$$platform" in \
	windows) [ -f "$$ltarget/libluajit.dll" ] || { echo "kcapp: missing runtime for $$target: $$ltarget/libluajit.dll" >&2; exit 1; }; cp "$$ltarget/libluajit.dll" "$$out/"; ;; \
	macos)   [ -f "$$ltarget/libluajit.dylib" ] || { echo "kcapp: missing runtime for $$target: $$ltarget/libluajit.dylib" >&2; exit 1; }; cp "$$ltarget/libluajit.dylib" "$$out/"; ;; \
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
echo "OK $$target"
endef

%:
	$(call compose)