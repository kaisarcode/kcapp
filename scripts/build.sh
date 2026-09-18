#!/bin/sh
set -eu

project=${1:-}

if [ -z "$project" ]; then
    echo "Usage: $0 <project>" >&2
    exit 1
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root_dir=$(dirname "$script_dir")
project_dir="$root_dir/proj/$project"

if [ ! -d "$project_dir" ]; then
    echo "kcapp: project not found: $project" >&2
    exit 1
fi

cd "$project_dir"
exec make all
