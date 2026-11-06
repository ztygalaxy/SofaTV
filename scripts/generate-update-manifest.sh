#!/bin/bash
set -eu
cd "$(cd "$(dirname "$0")/.." && pwd)"

output_dir="${1:-dist}"
notes_file="${2:-}"
version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION: $version" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[[ -d "$output_dir" ]] || { echo "Missing directory: $output_dir" >&2; exit 1; }

notes="${RELEASE_NOTES:-}"
if [[ -n "$notes_file" ]]; then
    [[ -f "$notes_file" ]] || { echo "Missing release notes: $notes_file" >&2; exit 1; }
    notes="$(<"$notes_file")"
fi

for arch in arm64 x86_64; do
    name="SofaTV-$version-$arch.zip"
    [[ -f "$output_dir/$name" ]] || { echo "Missing update archive: $name" >&2; exit 1; }
done

checksum() {
    if command -v shasum >/dev/null; then shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'
    else echo "shasum or sha256sum is required" >&2; exit 1
    fi
}
arm_sha256="$(checksum "$output_dir/SofaTV-$version-arm64.zip")"
intel_sha256="$(checksum "$output_dir/SofaTV-$version-x86_64.zip")"

temporary="$(mktemp "$output_dir/.update.json.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
jq -n \
    --arg version "$version" \
    --arg notes "$notes" \
    --arg arm_name "SofaTV-$version-arm64.zip" \
    --arg arm_sha256 "$arm_sha256" \
    --arg intel_name "SofaTV-$version-x86_64.zip" \
    --arg intel_sha256 "$intel_sha256" \
    '{schema:1, version:$version, notes:$notes, assets:{
        arm64:{name:$arm_name, sha256:$arm_sha256},
        x86_64:{name:$intel_name, sha256:$intel_sha256}
    }}' > "$temporary"
mv -f "$temporary" "$output_dir/update.json"
trap - EXIT
echo "Created $output_dir/update.json"
