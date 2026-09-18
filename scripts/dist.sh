#!/bin/sh
# kcapp distribution tool
# Summary: Packages built kcapp projects into distributable archives.
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU General Public License v3.0

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root_dir=$(dirname "$script_dir")
proj_dir="$root_dir/proj"
dist_dir="$root_dir/dist"

compute_sha256()
{
    file=$1

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    fi
}

compute_project_sha256()
{
    project_dir=$1
    checksum_file=$(mktemp)

    find "$project_dir" -type f -name '*.zip' |
        LC_ALL=C sort |
        while IFS= read -r file; do
            name=$(basename "$file")
            sha256=$(compute_sha256 "$file")
            printf '%s  %s\n' "$sha256" "$name"
        done > "$checksum_file"

    checksum=$(compute_sha256 "$checksum_file")
    rm -f "$checksum_file"

    printf '%s\n' "$checksum"
}

package_artifacts()
{
    mkdir -p "$dist_dir"

    for project_dir in "$proj_dir"/*; do
        [ -d "$project_dir" ] || continue

        bin_dir="$project_dir/bin"
        [ -d "$bin_dir" ] || continue

        project=$(basename "$project_dir")
        project_dist="$dist_dir/$project"

        echo "dist: packaging $project"

        mkdir -p "$project_dist"

        for arch_dir in "$bin_dir"/*; do
            [ -d "$arch_dir" ] || continue

            arch=$(basename "$arch_dir")

            for platform_dir in "$arch_dir"/*; do
                [ -d "$platform_dir" ] || continue

                platform=$(basename "$platform_dir")
                package="$project_dist/$project-$platform-$arch.zip"

                (
                    cd "$platform_dir"
                    zip -qr "$package" .
                )
            done
        done
    done
}

generate_manifest()
{
    manifest="$dist_dir/manifest.json"
    first=true

    echo "dist: generating manifest"

    {
        echo '{'
        echo '  "projects": {'

        for project_dir in "$dist_dir"/*; do
            [ -d "$project_dir" ] || continue

            project=$(basename "$project_dir")
            sha256=$(compute_project_sha256 "$project_dir")

            if [ "$first" = true ]; then
                first=false
            else
                echo ','
            fi

            printf '    "%s": {\n' "$project"
            printf '      "sha256": "%s"\n' "$sha256"
            printf '    }'
        done

        echo
        echo '  }'
        echo '}'
    } > "$manifest"
}

package_artifacts
generate_manifest
