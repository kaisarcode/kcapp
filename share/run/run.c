/**
 * run.c - LuaJIT application launcher
 * Summary: Starts Lua applications from their relocatable runtime directory.
 *
 * Author:  KaisarCode
 * Website: https://kaisarcode.com
 * License: https://www.gnu.org/licenses/gpl-3.0.html
 */

#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L

#include "run.h"

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <direct.h>
#include <windows.h>
#elif defined(__APPLE__)
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdlib.h>
#include <unistd.h>
#else
#include <limits.h>
#include <stdlib.h>
#include <unistd.h>
#endif

/**
 * Changes the process directory to the directory of its executable.
 * @return Zero on success or non-zero on failure.
 */
static int kc_run_set_root(void) {
    char path[PATH_MAX];
    char *separator;

#if defined(_WIN32)
    if (GetModuleFileNameA(NULL, path, sizeof(path)) == 0 ||
        GetModuleFileNameA(NULL, path, sizeof(path)) == sizeof(path)) {
        fprintf(stderr, "kcapp: unable to determine executable path\n");
        return 1;
    }
    separator = strrchr(path, '\\');
    if (separator == NULL) separator = strrchr(path, '/');
#elif defined(__APPLE__)
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0 || realpath(path, path) == NULL) {
        fprintf(stderr, "kcapp: unable to determine executable path\n");
        return 1;
    }
    separator = strrchr(path, '/');
#else
    ssize_t length = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (length < 0 || (size_t)length >= sizeof(path) - 1) {
        fprintf(stderr, "kcapp: unable to determine executable path\n");
        return 1;
    }
    path[length] = '\0';
    if (realpath(path, path) == NULL) {
        fprintf(stderr, "kcapp: unable to resolve executable path\n");
        return 1;
    }
    separator = strrchr(path, '/');
#endif

    if (separator == NULL) {
        fprintf(stderr, "kcapp: executable path has no directory\n");
        return 1;
    }
    *separator = '\0';

#if defined(_WIN32)
    if (_chdir(path) != 0) {
#else
    if (chdir(path) != 0) {
#endif
        fprintf(stderr, "kcapp: unable to enter application root\n");
        return 1;
    }
    return 0;
}

/**
 * Installs command-line arguments using LuaJIT script invocation semantics.
 * @param state Initialized Lua state.
 * @param argc Number of launcher arguments.
 * @param argv Launcher argument vector.
 * @return Zero on success.
 */
static int kc_run_set_arguments(lua_State *state, int argc, char **argv) {
    int index;

    lua_createtable(state, argc, 1);
    lua_pushstring(state, argv[0]);
    lua_rawseti(state, -2, -1);
    lua_pushliteral(state, "src/main.lua");
    lua_rawseti(state, -2, 0);
    for (index = 1; index < argc; index++) {
        lua_pushstring(state, argv[index]);
        lua_rawseti(state, -2, index);
    }
    lua_setglobal(state, "arg");
    return 0;
}

/**
 * Prepends application module directories to the Lua package path.
 * @param state Initialized Lua state.
 * @return Zero on success or non-zero on failure.
 */
static int kc_run_set_package_path(lua_State *state) {
    const char *path;

    lua_getglobal(state, "package");
    if (!lua_istable(state, -1)) {
        fprintf(stderr, "kcapp: Lua package table is unavailable\n");
        lua_pop(state, 1);
        return 1;
    }
    lua_getfield(state, -1, "path");
    path = lua_tostring(state, -1);
    if (path == NULL) {
        fprintf(stderr, "kcapp: Lua package path is unavailable\n");
        lua_pop(state, 2);
        return 1;
    }
    lua_pushfstring(state,
                    "./src/?.lua;./src/?/init.lua;%s",
                    path);
    lua_setfield(state, -3, "path");
    lua_pop(state, 1);
    return 0;
}

/**
 * Prints the Lua error stored at the top of the stack.
 * @param state Lua state holding an error object.
 * @return Non-zero failure status.
 */
static int kc_run_error(lua_State *state) {
    const char *message = lua_tostring(state, -1);

    fprintf(stderr, "kcapp: %s\n", message == NULL ? "Lua execution failed" : message);
    return 1;
}

/**
 * Starts src/main.lua from the executable directory.
 * @param argc Number of command-line arguments.
 * @param argv Command-line argument vector.
 * @return Zero on success or non-zero on failure.
 */
int kc_run_main(int argc, char **argv) {
    lua_State *state;
    int status;

    if (kc_run_set_root() != 0) return 1;

    state = luaL_newstate();
    if (state == NULL) {
        fprintf(stderr, "kcapp: unable to create Lua state\n");
        return 1;
    }
    luaL_openlibs(state);
    if (kc_run_set_package_path(state) != 0) {
        lua_close(state);
        return 1;
    }
    kc_run_set_arguments(state, argc, argv);
    status = luaL_loadfile(state, "src/main.lua");
    if (status == 0) status = lua_pcall(state, 0, LUA_MULTRET, 0);
    if (status != 0) status = kc_run_error(state);
    lua_close(state);
    return status;
}

/**
 * Starts the generic LuaJIT application launcher.
 * @param argc Number of command-line arguments.
 * @param argv Command-line argument vector.
 * @return Zero on success or non-zero on failure.
 */
int main(int argc, char **argv) {
    return kc_run_main(argc, argv);
}
