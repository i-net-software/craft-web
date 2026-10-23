#!/usr/bin/env bash
# Prints a GitHub Actions matrix (JSON) with every upstream release from apps.yml
# that this repository has not published yet. Prints {"include":[]} if there is none.
#
# A release counts as published when this repository has the tag <artifact-id>-<version>.
# The publish job creates that tag last, so a failed run is retried by the next one.
#
# Needs: gh (authenticated via GH_TOKEN), jq, yq, GITHUB_REPOSITORY.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"

semver='^[0-9]+\.[0-9]+\.[0-9]+$'
matrix='[]'

while read -r app; do
    upstream=$(jq -r '.upstream' <<<"$app")
    artifact=$(jq -r '."artifact-id"' <<<"$app")
    since=$(jq -r '.since' <<<"$app")
    template=$(jq -r '.asset' <<<"$app")

    # Final releases only, oldest first so versions reach Maven Central in order.
    releases=$(gh api "repos/${upstream}/releases?per_page=30" \
        --jq '[.[] | select(.draft == false and .prerelease == false)] | reverse | .[] | {tag: .tag_name, assets: [.assets[].name]}')

    while read -r release; do
        [ -n "$release" ] || continue
        tag=$(jq -r '.tag' <<<"$release")
        version=${tag#v}
        asset=${template//\{version\}/$version}

        [[ "$version" =~ $semver ]] || { echo "skip ${upstream} ${tag}: not a x.y.z version" >&2; continue; }
        [ "$(printf '%s\n%s\n' "$since" "$version" | sort -V | head -n1)" = "$since" ] || continue
        jq -e --arg a "$asset" '.assets | index($a)' <<<"$release" >/dev/null \
            || { echo "skip ${upstream} ${tag}: no asset ${asset}" >&2; continue; }
        if gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/${artifact}-${version}" >/dev/null 2>&1; then
            continue
        fi

        matrix=$(jq -c --argjson app "$app" --arg v "$version" --arg asset "$asset" \
            '. + [$app + {version: $v, asset: $asset, tag: ($app."artifact-id" + "-" + $v)}]' <<<"$matrix")
    done <<<"$releases"
done < <(yq -o=json -I=0 '.apps[]' apps.yml)

jq -c '{include: .}' <<<"$matrix"
