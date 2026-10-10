#!/usr/bin/env bash
# Migrated from V1.7 workflow step 07: Prepare DoorNet2 signing key
set -euo pipefail

# DoorNet2-V1.12 transitional policy:
# - If DOORNET2_SIGNING_KEY exists, use it as the persistent cross-version key.
# - If it is not configured yet, do NOT stop the build. Leave key-build absent
#   and let the OpenWrt/LEDE build system generate its normal per-build key.
#
# This transitional fallback keeps V1.4 buildable now. Before relying on
# cross-version signature continuity for future online upgrades, configure
# the persistent secret and remove this fallback in a later version.

rm -f \
  "${GITHUB_WORKSPACE}/key-build" \
  "${GITHUB_WORKSPACE}/key-build.pub" \
  "${GITHUB_WORKSPACE}/key-build.ucert"

if [ -z "${DOORNET2_SIGNING_KEY:-}" ]; then
    echo "WARNING: DOORNET2_SIGNING_KEY is not configured."
    echo "V1.4 will use the build system's temporary per-build signing key."
    echo "This is acceptable for this transitional build, but it does NOT"
    echo "establish long-term cross-version signature continuity."
    echo "DOORNET2_SIGNING_MODE=temporary-build-key" >> "$GITHUB_ENV"
    exit 0
fi

umask 077
printf '%s\n' "$DOORNET2_SIGNING_KEY" > "${GITHUB_WORKSPACE}/key-build"
chmod 600 "${GITHUB_WORKSPACE}/key-build"

test -s "${GITHUB_WORKSPACE}/key-build"

# Validate the usign secret key BEFORE compiling and derive the matching
# public key from the public half embedded inside the secret-key blob.
python3 <<'PY_SIGNKEY'
import base64
import hashlib
from pathlib import Path

secret_path = Path("key-build")
public_path = Path("key-build.pub")

lines = [line.strip() for line in secret_path.read_text().splitlines() if line.strip()]
if len(lines) < 2 or not lines[0].startswith("untrusted comment:"):
    raise SystemExit("ERROR: invalid usign secret-key header.")

try:
    sec = base64.b64decode(lines[-1], validate=True)
except Exception as exc:
    raise SystemExit(f"ERROR: invalid usign secret-key base64: {exc}")

if len(sec) != 104:
    raise SystemExit(f"ERROR: unexpected usign secret-key size: {len(sec)}")
if sec[0:2] != b"Ed":
    raise SystemExit("ERROR: signing key is not an Ed25519 usign key.")
if sec[2:4] != b"BK":
    raise SystemExit("ERROR: unsupported usign secret-key KDF format.")
if sec[4:8] != b"\x00\x00\x00\x00":
    raise SystemExit("ERROR: password-protected usign keys are not supported.")

secret_material = sec[40:104]
if sec[24:32] != hashlib.sha512(secret_material).digest()[:8]:
    raise SystemExit("ERROR: usign secret key checksum is invalid.")

fingerprint = sec[32:40]
public_key = secret_material[32:64]

pub_blob = b"Ed" + fingerprint + public_key
pub_b64 = base64.b64encode(pub_blob).decode("ascii")

public_path.write_text(
    "untrusted comment: DoorNet2 persistent public key\n"
    + pub_b64
    + "\n"
)

printable_fp = "".join(f"{b:02x}" for b in fingerprint[::-1])
print("Persistent signing secret-key structure: OK")
print("Derived signing fingerprint:", printable_fp)
PY_SIGNKEY

chmod 644 "${GITHUB_WORKSPACE}/key-build.pub"
test -s "${GITHUB_WORKSPACE}/key-build.pub"

echo "DOORNET2_SIGNING_MODE=persistent-key" >> "$GITHUB_ENV"
echo "Persistent DoorNet2 signing key restored and public key derived."
echo "Private key: present (content hidden)"
echo "Public key:  derived from private key"
