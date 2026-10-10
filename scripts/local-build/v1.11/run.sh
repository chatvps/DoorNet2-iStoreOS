#!/usr/bin/env bash
set -euo pipefail

mode="${1:-check}"

case "$mode" in
  check|build) ;;
  *)
    echo "Usage: $0 [check|build]" >&2
    exit 2
    ;;
esac

repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"

[[ -n "$repo" ]] || {
  echo 'ERROR: run inside DoorNet2 source repository' >&2
  exit 1
}

cd "$repo"

[[ "$(git remote get-url origin)" == *'chatvps/DoorNet2-iStoreOS'* ]] || {
  echo 'ERROR: wrong git remote' >&2
  exit 1
}

[[ "$(uname -m)" == x86_64 ]] || {
  echo 'ERROR: expected x86_64 host' >&2
  exit 1
}

[[ -f r4.bin.gz ]] || {
  echo 'ERROR: missing R4 bootloader asset' >&2
  exit 1
}

assert_sha='66674de2c4ba7aab7ee6df41b1bcc604be0d3b8a274251b97f8a3be06c7086dd'

[[ "$(sha256sum r4.bin.gz | awk '{print $1}')" == "$assert_sha" ]] || {
  echo 'ERROR: R4 asset SHA256 mismatch' >&2
  exit 1
}

echo '===== DoorNet2 V1.11 static checks ====='

count=0

for f in \
  scripts/local-build/v1.11/steps/*.sh \
  scripts/local-build/v1.11/inside-container.sh
do
  bash -n "$f"
  count=$((count+1))
done

bash -n scripts/local-build/v1.11/run.sh

echo "OK: $count shell scripts checked"
echo 'OK: R4 compressed SHA256 matches R4 baseline'
echo "Source revision: $(git rev-parse --short HEAD)"
echo 'Docker image: doornet2-build:ubuntu22.04'

if [[ "$mode" == check ]]; then
  echo 'PRECHECK OK (no build, no publication)'
  exit 0
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo 'ERROR: tracked source contains uncommitted changes.' >&2
  git status --short
  exit 1
fi

branch="$(git branch --show-current || true)"

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  ref="${GITHUB_REF_NAME:-$branch}"

  echo "GitHub Actions source ref: $ref"

else
  [[ "$branch" == main ]] || {
    echo 'ERROR: local release builds must run from main' >&2
    echo "Current branch: $branch" >&2
    exit 1
  }
fi

keyfile="${DOORNET2_SIGNING_KEY_FILE:-}"
args=()

if [[ -n "$keyfile" ]]; then
  [[ -f "$keyfile" && -r "$keyfile" ]] || {
    echo 'ERROR: DOORNET2_SIGNING_KEY_FILE not readable' >&2
    exit 1
  }

  args+=(
    --mount
    "type=bind,source=$(realpath "$keyfile"),target=/run/secrets/doornet2-signing-key,readonly"
  )

  echo 'Persistent DoorNet2 signing key enabled.'
else
  echo 'WARNING: No persistent signing key configured.'
  echo 'WARNING: CI test build may use a temporary build key.'
fi

for f in \
  '/key-build' \
  '/key-build.pub' \
  '/key-build.ucert' \
  '/dl/' \
  '/.ccache/' \
  '/bin/'
do
  grep -Fxq "$f" .git/info/exclude 2>/dev/null || \
    printf '%s\n' "$f" >> .git/info/exclude
done

if [[ -n "${DOORNET2_LOG_DIR:-}" ]]; then
  logdir="$DOORNET2_LOG_DIR"
elif [[ -n "${RUNNER_TEMP:-}" ]]; then
  logdir="$RUNNER_TEMP/doornet2-build-logs"
else
  logdir="$HOME/Projects/DoorNet2-build-logs"
fi

mkdir -p "$logdir"

log="$logdir/DoorNet2-V1.11-$(date +%Y%m%d-%H%M%S).log"

echo "Logging build output to: $log"

sudo docker image inspect \
  doornet2-build:ubuntu22.04 \
  >/dev/null 2>&1 || {
    echo 'ERROR: Docker image doornet2-build:ubuntu22.04 does not exist.' >&2
    exit 1
  }

sudo docker run --rm --init \
  --mount "type=bind,source=$repo,target=/workspace" \
  "${args[@]}" \
  -e GITHUB_REPOSITORY=chatvps/DoorNet2-iStoreOS \
  -e GITHUB_ACTIONS="${GITHUB_ACTIONS:-}" \
  -e GITHUB_REF_NAME="${GITHUB_REF_NAME:-$branch}" \
  -e GITHUB_SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}" \
  -e DOORNET2_VERSION="DoorNet2-V1.11" \
  -e DOORNET2_JOBS="${DOORNET2_JOBS:-4}" \
  -e CCACHE_DIR="/workspace/.ccache" \
  -e CCACHE_COMPRESS="1" \
  -w /workspace \
  doornet2-build:ubuntu22.04 \
  bash scripts/local-build/v1.11/inside-container.sh \
  2>&1 | tee "$log"
