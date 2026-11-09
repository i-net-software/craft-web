#!/usr/bin/env bash
# Prints a GitHub Actions matrix (JSON) with the latest eligible upstream release per app from apps.yml
# that this repository has not published yet. Prints {"include":[]} if there is none.
#
# Git tags and Maven Central both prevent duplicate versions. A successful publication
# starts a seven-day cooldown per artifact. Manual runs can override the cooldown
# with OVERRIDE_COOLDOWN=true; duplicate/reservation checks always remain active.
#
# Needs: gh (authenticated via GH_TOKEN), curl, python3, jq, yq, GITHUB_REPOSITORY.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"

semver='^[0-9]+\.[0-9]+\.[0-9]+$'
matrix='[]'
now=$(date +%s)
cooldown=$((7 * 24 * 60 * 60))
# Fetch once, paginate, and fail closed on API errors instead of treating them as missing tags.
tags=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/tags?per_page=100" --jq '.[].name')
published=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/releases?per_page=100" \
    --jq '.[] | {tag: .tag_name, at: (.published_at // .created_at)}' | jq -s '.')
tags=$(printf '%s\n%s' "$tags" "$(jq -r '.[].tag' <<<"$published")")
apps=$(yq -o=json -I=0 '.apps[]' apps.yml)

while read -r app; do
    upstream=$(jq -r '.upstream' <<<"$app")
    artifact=$(jq -r '."artifact-id"' <<<"$app")
    since=$(jq -r '.since' <<<"$app")
    template=$(jq -r '.asset' <<<"$app")

    # Central is authoritative even if publishing succeeded but creating the GitHub tag failed.
    metadata=$(mktemp)
    status=$(curl --silent --show-error --location --retry 3 --output "$metadata" --write-out '%{http_code}' \
        "https://repo.maven.apache.org/maven2/de/inetsoftware/${artifact}/maven-metadata.xml")
    case "$status" in
        200) central=$(python3 scripts/read-metadata.py "$metadata") ;;
        404) central='{"versions":[],"updated":0}' ;;
        *) rm -f "$metadata"; echo "Central metadata failed: HTTP ${status}" >&2; exit 1 ;;
    esac
    rm -f "$metadata"
    last=$(jq -r --arg prefix "${artifact}-" \
        '[.[] | select(.tag | startswith($prefix)) | .at | fromdateiso8601] | max // 0' <<<"$published")
    central_updated=$(jq -r '.updated' <<<"$central")
    (( central_updated <= last )) || last=$central_updated
    if [[ "${OVERRIDE_COOLDOWN:-false}" != true ]] && (( last > 0 && now - last < cooldown )); then
        echo "skip ${artifact}: published within the last seven days" >&2
        continue
    fi

    # Final releases only; select the newest eligible version below.
    releases=$(gh api --paginate "repos/${upstream}/releases?per_page=100" \
        --jq '.[] | select(.draft == false and .prerelease == false) | {tag: .tag_name, assets: [.assets[].name]}' \
        | jq -sc 'sort_by(.tag | ltrimstr("v") | split(".") | map(tonumber? // -1)) | reverse | .[]')

    while read -r release; do
        [ -n "$release" ] || continue
        tag=$(jq -r '.tag' <<<"$release")
        version=${tag#v}
        asset=${template//\{version\}/$version}

        [[ "$version" =~ $semver ]] || { echo "skip ${upstream} ${tag}: not a x.y.z version" >&2; continue; }
        [ "$(printf '%s\n%s\n' "$since" "$version" | sort -V | head -n1)" = "$since" ] || continue
        jq -e --arg a "$asset" '.assets | index($a)' <<<"$release" >/dev/null \
            || { echo "skip ${upstream} ${tag}: no asset ${asset}" >&2; continue; }
        if jq -e --arg v "$version" '.versions | index($v)' <<<"$central" >/dev/null \
            || [[ $'\n'"$tags"$'\n' == *$'\n'"${artifact}-${version}"$'\n'* ]]; then
            # The newest eligible release is already published; do not backfill older ones.
            break
        fi

        matrix=$(jq -c --argjson app "$app" --arg v "$version" --arg asset "$asset" \
            '. + [$app + {version: $v, asset: $asset, tag: ($app."artifact-id" + "-" + $v)}]' <<<"$matrix")
        break  # At most the newest version per artifact; never drain a release backlog.
    done <<<"$releases"
done <<<"$apps"

jq -c '{include: .}' <<<"$matrix"
