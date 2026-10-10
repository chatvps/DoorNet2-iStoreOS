#!/usr/bin/env bash
set -euo pipefail

cd /workspace
[[ "$(id -un)" == "builder" ]] || { echo "ERROR: OpenWrt must build as builder" >&2; exit 1; }
[[ "$GITHUB_REPOSITORY" == "chatvps/DoorNet2-iStoreOS" ]] || { echo "ERROR: wrong repo" >&2; exit 1; }
[[ "$(git rev-parse --show-toplevel)" == "/workspace" ]] || { echo "ERROR: source mount invalid" >&2; exit 1; }
[[ -f r4.bin.gz ]] || { echo "ERROR: r4.bin.gz missing" >&2; exit 1; }

export GITHUB_WORKSPACE=/workspace
export GITHUB_SHA="$(git rev-parse HEAD)"
export GITHUB_ENV="$(mktemp /tmp/doornet2-github-env.XXXXXX)"
trap 'rm -f "$GITHUB_ENV"' EXIT
export DOORNET2_JOBS="${DOORNET2_JOBS:-2}"
export PATH="${GITHUB_WORKSPACE}/staging_dir/host/bin:${PATH}"

# Read only simple one-line environment assignments emitted by the migrated
# GitHub Actions steps; no eval/source of the environment file.
load_env() {
    local k v
    while IFS='=' read -r k v || [[ -n "$k" ]]; do
        [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
            echo "ERROR: invalid exported variable name: $k" >&2; exit 1;
        }
        export "$k=$v"
    done < "$GITHUB_ENV"
}

if [[ -r /run/secrets/doornet2-signing-key ]]; then
    export DOORNET2_SIGNING_KEY="$(cat /run/secrets/doornet2-signing-key)"
fi

for stage in /workspace/scripts/local-build/v1.1.1/steps/*.sh; do
    case "$(basename "$stage")" in
        56-*) ;; # handled after audits/artifacts but before publishing
    esac
    echo
    echo "===== $(date -Is) START $(basename "$stage") ====="
    bash "$stage"
    load_env
    echo "===== $(date -Is) OK $(basename "$stage") ====="
done

echo
printf 'LOCAL BUILD AND AUDIT COMPLETE: %s\n' "${DOORNET2_VERSION:-unknown}"
echo 'No GitHub release or OPKG branch was published.'
echo 'Do not flash eMMC. Perform separate static validation and TF-only test first.'
