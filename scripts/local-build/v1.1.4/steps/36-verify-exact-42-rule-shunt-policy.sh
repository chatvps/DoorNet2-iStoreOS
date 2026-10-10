#!/usr/bin/env bash
# Migrated from V1.7 workflow step 36: Verify exact 42-rule shunt policy
set -euo pipefail

PRESET="files/etc/uci-defaults/zzza-doornet2-shunt-presets"
test -x "$PRESET"
sh -n "$PRESET"

python3 - "$PRESET" <<'PY_SHUNT'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

expected = [
    "DN_WeChatTencent",
    "DN_ChatGPT_Login",
    "DN_OpenAI",
    "DN_GitHub",
    "DN_GoogleWork",
    "DN_GoogleAI",
    "DN_YouTube",
    "DN_Netflix",
    "DN_Disney",
    "DN_MaxHBO",
    "DN_PrimeVideo",
    "DN_Twitter",
    "DN_Telegram",
    "DN_Google",
    "DN_TikTok",
    "DN_PlayStation",
    "DN_Nintendo",
    "DN_Instagram",
    "DN_Signal",
    "DN_Spotify",
    "DN_Slack",
    "DN_DirectGame",
    "DN_ProxyGame",
    "DN_AIGC",
    "DN_Streaming",
    "DN_Proxy",
    "DN_Direct",
    "DN_LINE",
    "DN_WhatsApp",
    "DN_Discord",
    "DN_Facebook",
    "DN_Reddit",
    "DN_Claude",
    "DN_Perplexity",
    "DN_Copilot",
    "DN_Grok",
    "DN_Apple",
    "DN_Microsoft",
    "DN_Zoom",
    "DN_Notion",
    "DN_Dropbox",
    "DN_Xbox",
]

actual = re.findall(
    r'add_rule "\$cfg" (DN_[A-Za-z0-9_]+) ',
    text,
)

if actual != expected:
    print("ERROR: PassWall/PassWall2 built-in rule order mismatch.")
    print("Expected:", expected)
    print("Actual:  ", actual)
    raise SystemExit(1)

if len(actual) != 42 or len(set(actual)) != 42:
    raise SystemExit("ERROR: shunt policy must contain exactly 42 unique rules.")

required_direct = [
    "DN_WeChatTencent:_direct",
    "DN_DirectGame:_direct",
    "DN_Direct:_direct",
]
for item in required_direct:
    if item not in text:
        raise SystemExit(f"ERROR: required direct binding missing: {item}")

for domain in (
    "wechat.com",
    "weixin.qq.com",
    "qpic.cn",
    "gtimg.com",
    "idqqimg.com",
    "qlogo.cn",
):
    if domain not in text:
        raise SystemExit(
            f"ERROR: required WeChat/Tencent direct domain missing: {domain}"
        )

if "api.example.com" in text:
    raise SystemExit("ERROR: test domain api.example.com must never ship.")

print("OK: exact 42-rule order verified.")
print("OK: WeChatTencent/DirectGame/Direct are pinned to direct.")
PY_SHUNT
