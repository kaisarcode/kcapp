#!/bin/sh
# kcapp project initializer
# Summary: Creates a minimal kcapp project without generated output.
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU General Public License v3.0

set -eu

# Prints the project creation command syntax.
# @return Non-zero failure status.
usage()
{
    echo "Usage: $0 <project>" >&2
    return 1
}

# Validates a project directory and executable name.
# @param project Candidate project name.
# @return Zero when the name is valid or non-zero otherwise.
valid_project_name()
{
    project=$1

    case "$project" in
        [A-Za-z0-9]*)
            ;;
        *)
            return 1
            ;;
    esac
    case "$project" in
        *[!A-Za-z0-9_-]*)
            return 1
            ;;
    esac
    return 0
}

# Creates the minimal project skeleton from the shared Makefile template.
# @param project Project name.
# @return Zero on success or non-zero on failure.
create_project()
{
    project=$1
    script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
    root_dir=$(dirname "$script_dir")
    project_dir="$root_dir/proj/$project"
    template="$root_dir/share/init/Makefile"
    fence="\`\`\`"

    if [ -e "$project_dir" ] || [ -L "$project_dir" ]; then
        echo "kcapp: project already exists: $project" >&2
        return 1
    fi
    if [ ! -f "$template" ]; then
        echo "kcapp: missing project template: $template" >&2
        return 1
    fi

    mkdir -p "$project_dir/src"
    cp "$template" "$project_dir/Makefile"
    printf '{\n  "kclib": []\n}\n' > "$project_dir/config.json"
    printf 'local kcapp = require("kcapp")\n\nprint("Hello from %s")\n' "$project" > "$project_dir/src/main.lua"
    printf '%s\n' "# $project" "" "$project is a kcapp application." "" "## Usage" "" "${fence}sh" "./$project" "$fence" > "$project_dir/README.md"
    echo "Created proj/$project"
    return 0
}

# Validates arguments and creates a project.
# @param argc Command-line argument count.
# @param argv Command-line argument vector.
# @return Zero on success or non-zero on failure.
main()
{
    if [ "$#" -ne 1 ]; then
        usage
        return 1
    fi
    if ! valid_project_name "$1"; then
        usage
        return 1
    fi
    create_project "$1"
}

main "$@"
