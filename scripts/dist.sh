#!/bin/sh
# kcapp distribution tool
# Summary: Packages built kcapp projects and generates distribution metadata.
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU General Public License v3.0

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root_dir=$(dirname "$script_dir")
proj_dir="$root_dir/proj"
dist_dir="$root_dir/dist"

# Computes the SHA-256 digest of a file.
# @param file Path to the file.
# @return 0 on success; the digest is written to stdout.
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

# Computes the SHA-256 digest representing a build directory.
# SHA256SUM.txt itself is excluded from the digest.
# @param build_dir Build directory.
# @return 0 on success; the digest is written to stdout.
compute_build_sha256()
{
    build_dir=$1
    checksum_file=$(mktemp)

    find "$build_dir" -type f ! -name 'SHA256SUM.txt' |
        LC_ALL=C sort |
        while IFS= read -r file; do
            rel_path=${file#"$build_dir"/}
            file_sha256=$(compute_sha256 "$file")
            printf '%s  %s\n' "$file_sha256" "$rel_path"
        done > "$checksum_file"

    build_sha256=$(compute_sha256 "$checksum_file")
    rm -f "$checksum_file"

    printf '%s\n' "$build_sha256"
}

# Packages every built project target into a distributable ZIP archive.
# Each package receives SHA256SUM.txt containing the build digest.
# @param proj_dir Projects directory.
# @param dist_dir Distribution directory.
# @return 0 on success.
package_artifacts()
{
    source_dir=$1
    target_dir=$2

    mkdir -p "$target_dir"

    for project_dir in "$source_dir"/*; do
        [ -d "$project_dir" ] || continue

        bin_dir="$project_dir/bin"
        [ -d "$bin_dir" ] || continue

        project=$(basename "$project_dir")
        project_dist="$target_dir/$project"

        echo "Processing $project..."

        mkdir -p "$project_dist"

        for arch_dir in "$bin_dir"/*; do
            [ -d "$arch_dir" ] || continue

            arch=$(basename "$arch_dir")

            for platform_dir in "$arch_dir"/*; do
                [ -d "$platform_dir" ] || continue

                platform=$(basename "$platform_dir")
                package_name="$project-$platform-$arch.zip"
                package="$project_dist/$package_name"
                build_dir=$(mktemp -d)

                cp -R "$platform_dir"/. "$build_dir"/

                build_sha256=$(compute_build_sha256 "$build_dir")
                printf '%s\n' "$build_sha256" > "$build_dir/SHA256SUM.txt"
                rm -f "$package"

                (
                    cd "$build_dir"
                    zip -qr "$package" .
                )

                rm -rf "$build_dir"
            done
        done

        echo "    [+] Packages collected in $project_dist/"
    done

    return 0
}

# Reads the build digest stored inside a package.
# @param package ZIP package path.
# @return 0 on success; the digest is written to stdout.
read_package_sha256()
{
    package=$1

    unzip -p "$package" SHA256SUM.txt
}

# Writes manifest.json for a single project with package build digests.
# @param project_dist Project distribution directory.
# @param project Project name.
# @return 0 on success.
generate_project_manifest()
{
    project_dist=$1
    project=$2
    manifest_file="$project_dist/manifest.json"
    first_package=true

    echo "Generating $project/manifest.json..."

    {
        echo '{'
        echo "  \"updated_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
        echo "  \"timestamp\": $(date -u +%s),"
        echo '  "packages": {'

        for package in "$project_dist"/*.zip; do
            [ -f "$package" ] || continue

            package_name=$(basename "$package")
            build_sha256=$(read_package_sha256 "$package")

            if [ "$first_package" = true ]; then
                first_package=false
            else
                echo ','
            fi

            printf '    "%s": {\n' "$package_name"
            printf '      "sha256": "%s"\n' "$build_sha256"
            printf '    }'
        done

        echo
        echo '  }'
        echo '}'
    } > "$manifest_file"

    return 0
}

# Packages project artifacts and generates distribution metadata.
# @return 0 on success.
main()
{
    package_artifacts "$proj_dir" "$dist_dir"

    for project_dir in "$dist_dir"/*/; do
        [ -d "$project_dir" ] || continue
        project=$(basename "$project_dir")
        generate_project_manifest "$project_dir" "$project"
    done

    echo "Done."
}

main "$@"
