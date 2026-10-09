#!/usr/bin/env bash
set -euo pipefail

mode="${1:-check}"
case "$mode" in check|build) ;; *) echo "Usage: $0 [check|build]" >&2; exit 2;; esac
repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$repo" ]] || { echo 'ERROR: run inside DoorNet2 source repository' >&2; exit 1; }
cd "$repo"
[[ "$(git remote get-url origin)" == *'chatvps/DoorNet2-iStoreOS'* ]] || {
  echo 'ERROR: wrong git remote' >&2; exit 1;
}
[[ "$(uname -m)" == x86_64 ]] || { echo 'ERROR: expected x86_64 host' >&2; exit 1; }
[[ -f r4.bin.gz ]] || { echo 'ERROR: missing R4 bootloader asset' >&2; exit 1; }
assert_sha='66674de2c4ba7aab7ee6df41b1bcc604be0d3b8a274251b97f8a3be06c7086dd'
[[ "$(sha256sum r4.bin.gz | awk '{print $1}')" == "$assert_sha" ]] || {
  echo 'ERROR: R4 asset SHA256 mismatch' >&2; exit 1;
}

echo '===== Local build script static checks ====='
count=0
for f in scripts/local-build/v1.8/steps/*.sh scripts/local-build/v1.8/inside-container.sh; do
  bash -n "$f" || exit 1
  count=$((count+1))
done
bash -n scripts/local-build/v1.8/run.sh
echo "OK: $count shell scripts checked"
echo 'OK: R4 compressed SHA256 matches R4 baseline'
echo "Source revision: $(git rev-parse --short HEAD)"
echo "Docker image: doornet2-build:ubuntu22.04"

if [[ "$mode" == check ]]; then
  echo 'PRECHECK OK (no build, no publication)'
  exit 0
fi

# Avoid producing a published firmware with an inaccurate source SHA/version.
[[ -z "$(git status --porcelain)" ]] || {
  echo 'ERROR: commit your V1.8 script changes and push before building.' >&2
  git status --short
  exit 1
}
[[ "$(git branch --show-current)" == main ]] || {
  echo 'ERROR: expected main branch' >&2; exit 1;
}

# GitHub does not provide the signing secret back to users. Optionally mount
# an existing local usign private key, and NEVER put it into a command argument.
keyfile="${DOORNET2_SIGNING_KEY_FILE:-}"
args=()
if [[ -n "$keyfile" ]]; then
  [[ -f "$keyfile" && -r "$keyfile" ]] || {
    echo 'ERROR: DOORNET2_SIGNING_KEY_FILE not readable' >&2; exit 1;
  }
  args+=(--mount "type=bind,source=$(realpath "$keyfile"),target=/run/secrets/doornet2-signing-key,readonly")
else
  echo 'WARNING: No persistent signing key configured. This build uses a temporary build key.'
  echo 'WARNING: Do not rely on this build for cross-version signed OTA until trust is configured.'
fi

# Workflows generate key-build and other generated files in the checkout.
# Exclude these from casual git add -A; never commit or share private keys.
for f in '/key-build' '/key-build.pub' '/key-build.ucert'; do
  grep -Fxq "$f" .git/info/exclude || printf '%s\n' "$f" >> .git/info/exclude
done

logdir="${DOORNET2_LOG_DIR:-$HOME/Projects/DoorNet2-build-logs}"
mkdir -p "$logdir"
log="$logdir/DoorNet2-V1.8-$(date +%Y%m%d-%H%M%S).log"
echo "Logging build output to: $log"

# All steps execute inside ONE container so /tmp markers and GITHUB_ENV persist.
# Source/build outputs live on the bind mount, so they survive container exit.
sudo docker run --rm --init \
  --mount "type=bind,source=$repo,target=/workspace" \
  "${args[@]}" \
  -e GITHUB_REPOSITORY=chatvps/DoorNet2-iStoreOS \
  -e DOORNET2_JOBS="${DOORNET2_JOBS:-2}" \
  -w /workspace \
  doornet2-build:ubuntu22.04 \
  bash scripts/local-build/v1.8/inside-container.sh \
  2>&1 | tee "$log"
