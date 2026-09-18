/**
 * run.h - LuaJIT application launcher
 * Summary: Public entry point for the portable LuaJIT launcher.
 *
 * Author:  KaisarCode
 * Website: https://kaisarcode.com
 * License: https://www.gnu.org/licenses/gpl-3.0.html
 */

#ifndef KC_RUN_H
#define KC_RUN_H

/**
 * Starts src/main.lua from the executable directory.
 * @param argc Number of command-line arguments.
 * @param argv Command-line argument vector.
 * @return Zero on success or non-zero on failure.
 */
int kc_run_main(int argc, char **argv);

#endif
