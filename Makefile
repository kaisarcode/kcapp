## Makefile
## Summary: Composes portable runnable directories for LuaJIT desktop apps.
## Author:  KaisarCode
## Website: https://kaisarcode.com
## License: GNU GPL v3

PROJECT ?= demo

KCAPP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

KCLIB_DIST_DIR ?= $(abspath $(KCAPP_DIR)/../kclib/dist)
LUAJIT_DIST_DIR ?= $(abspath $(KCAPP_DIR)/../luajit/dist)

PROJECT_DIR := $(KCAPP_DIR)/projects/$(PROJECT)
CONFIG := $(PROJECT_DIR)/config.json
SRC_DIR := $(PROJECT_DIR)/src
OUT_DIR := $(PROJECT_DIR)/bin

KC_LIBS := $(if $(wildcard $(CONFIG)),$(shell awk -v key='"kclib"' '{ buf = buf " " $$0 } END { if (match(buf, key "[[:space:]]*:[[:space:]]*\\[")) { s = substr(buf, RSTART + RLENGTH); while (match(s, /"[^"]*"/)) { v = substr(s, RSTART + 1, RLENGTH - 2); print v; s = substr(s, RSTART + RLENGTH) } } }' "$(CONFIG)"),)

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo 'Usage:'
	@echo '  make PROJECT=NAME <arch>/<platform>'
	@echo 'Example:'
	@echo '  make PROJECT=demo x86_64/linux'
	@echo 'Output:'
	@echo '  projects/$(PROJECT)/bin/<arch>/<platform>/'

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
case '$(PROJECT)' in \
	*/*) echo "kcapp: invalid project name '$(PROJECT)'" >&2; exit 1 ;; \
esac; \
[ -d '$(PROJECT_DIR)' ] || { echo "kcapp: project '$(PROJECT)' not found: $(PROJECT_DIR)" >&2; exit 1; }; \
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
echo "kcapp: composing $$target -> $$out"; \
mkdir -p "$$out/lib"; \
cp -R '$(SRC_DIR)/.' "$$out/"; \
cp "$$ltarget/$$lexec" "$$out/$$lexec"; \
chmod +x "$$out/$$lexec"; \
for dep in $(KC_LIBS); do \
	ddir='$(KCLIB_DIST_DIR)/'"$$dep"'.c/'"$$arch"'/'"$$platform"; \
	cdef="$$ddir/lib$$dep.cdef"; \
	lib="$$ddir/lib$$dep$$lext"; \
	[ -f "$$cdef" ] || { echo "kcapp: missing cdef for $$dep at $$target: $$cdef" >&2; exit 1; }; \
	[ -f "$$lib" ] || { echo "kcapp: missing library for $$dep at $$target: $$lib" >&2; exit 1; }; \
	cp "$$cdef" "$$out/lib/"; \
	cp "$$lib" "$$out/lib/"; \
done; \
echo "kcapp: composed $$target"
endef

%:
	$(call compose)