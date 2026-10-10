#!/usr/bin/env bash
# Migrated from V1.7 workflow step 19: Seed PassWall and PassWall2 shunt presets
set -e

mkdir -p \
  files/etc/uci-defaults \
  files/lib/upgrade/keep.d

cat > files/etc/uci-defaults/zzza-doornet2-shunt-presets <<'EOF'
#!/bin/sh

# DoorNet2 preset rules are seeded once.  The marker is preserved by
# sysupgrade so later firmware upgrades do not overwrite user-selected
# nodes, edited rules, or the user's PassWall/PassWall2 configuration.
PRESET_MARKER="/etc/doornet2-shunt-presets-v2"
NETWORK_MARKER="/etc/doornet2-user-network-initialized"

[ -e "$PRESET_MARKER" ] && exit 0

RETAINED=0
[ -e "$NETWORK_MARKER" ] && RETAINED=1

add_rule()
{
    cfg="$1"
    id="$2"
    remarks="$3"
    domains="$4"
    ips="$5"

    # During a retained upgrade, never overwrite an existing rule
    # with the same ID.  On a clean install, create the known preset
    # deterministically from scratch.
    if [ "$RETAINED" = "1" ] && uci -q get "$cfg.$id" >/dev/null 2>&1; then
        return 0
    fi

    uci -q delete "$cfg.$id"
    uci -q set "$cfg.$id=shunt_rules"
    uci -q set "$cfg.$id.remarks=$remarks"
    uci -q set "$cfg.$id.network=tcp,udp"

    if [ -n "$domains" ]; then
        domain_list="$(
            printf '%s' "$domains" \
              | tr ',' '\n' \
              | sed '/^$/d;s/^/domain:/'
        )"
        uci -q set "$cfg.$id.domain_list=$domain_list"
    fi

    if [ -n "$ips" ]; then
        ip_list="$(
            printf '%s' "$ips" \
              | tr ',' '\n' \
              | sed '/^$/d'
        )"
        uci -q set "$cfg.$id.ip_list=$ip_list"
    fi
}

seed_config()
{
    cfg="$1"
    [ -f "/etc/config/$cfg" ] || return 0

    # On a clean PassWall install, remove only its untouched stock
    # myshunt entry so LuCI does not show two nodes named 分流总节点.
    # Retained upgrades never delete an existing user section.
    if [ "$cfg" = "passwall" ] && [ "$RETAINED" = "0" ]; then
        if [ "$(uci -q get passwall.myshunt.remarks)" = "分流总节点" ] && \
           [ "$(uci -q get passwall.myshunt.protocol)" = "_shunt" ]; then
            uci -q delete passwall.myshunt
        fi
    fi

    # PassWall2 ships an example SOCKS node plus an example shunt node.
    # Remove only those untouched stock examples on a clean install so
    # LuCI exposes one clean user-facing node named “分流总节点”.
    if [ "$cfg" = "passwall2" ] && [ "$RETAINED" = "0" ]; then
        if [ "$(uci -q get passwall2.rulenode.remarks)" = "rulenode" ] && \
           [ "$(uci -q get passwall2.rulenode.protocol)" = "_shunt" ]; then
            uci -q delete passwall2.rulenode
        fi
        if [ "$(uci -q get passwall2.examplenode.remarks)" = "Example" ] && \
           [ "$(uci -q get passwall2.examplenode.address)" = "passwall2.github" ]; then
            uci -q delete passwall2.examplenode
        fi
    fi

    # DoorNet2 built-in shunt rules.
    # Keep this exact order identical for PassWall and PassWall2.
    # WeChatTencent is intentionally rule #1 and is pinned to direct
    # so WeChat/QQ/Tencent photos, video and CDN traffic do not follow
    # a proxy node and become unnecessarily slow.

    #  1. WeChatTencent
    add_rule "$cfg" DN_WeChatTencent "WeChatTencent" \
      "wechat.com,wechatapp.com,weixin.qq.com,wx.qq.com,weixinbridge.com,qq.com,qzone.qq.com,qpic.cn,gtimg.com,idqqimg.com,qlogo.cn,qqmail.com,tenpay.com" ""

    #  2. ChatGPTLogin
    add_rule "$cfg" DN_ChatGPT_Login "ChatGPTLogin" \
      "auth.openai.com,chatgpt.com,ct.sendgrid.net,intercom.io,intercomcdn.com,oaistatic.com,oaiusercontent.com,openai.com,oaistatsig.com,auth0.openai.com,cdn.openaimerge.com,cdn.workos.com,challenges.cloudflare.com,forwarder.workos.com,humb.apple.com,images.workoscdn.com,js.intercomcdn.com,js.stripe.com,o207216.ingest.sentry.io,o33249.ingest.sentry.io,rum.browser-intake-datadoghq.com,setup.auth.openai.com,setup.workos.com,workos.imgix.net" ""

    #  3. OpenAI
    add_rule "$cfg" DN_OpenAI "OpenAI" \
      "openai.com,chatgpt.com,auth.openai.com,oaistatic.com,oaiusercontent.com,oaistatsig.com" ""

    #  4. GitHub
    add_rule "$cfg" DN_GitHub "GitHub" \
      "github.com,githubusercontent.com,githubassets.com,github.io" ""

    #  5. GoogleWork
    add_rule "$cfg" DN_GoogleWork "GoogleWork" \
      "gmail.com,mail.google.com,drive.google.com,docs.google.com,sheets.google.com,slides.google.com,meet.google.com,calendar.google.com,workspace.google.com" ""

    #  6. GoogleAI
    add_rule "$cfg" DN_GoogleAI "GoogleAI" \
      "gemini.google.com,ai.google.dev,generativelanguage.googleapis.com,aistudio.google.com,deepmind.google" ""

    #  7. YouTube
    add_rule "$cfg" DN_YouTube "YouTube" \
      "youtube.com,youtu.be,ytimg.com,googlevideo.com,youtube-nocookie.com" ""

    #  8. Netflix
    add_rule "$cfg" DN_Netflix "Netflix" \
      "netflix.com,nflxvideo.net,nflximg.net,nflxext.com,nflxso.net" ""

    #  9. Disney
    add_rule "$cfg" DN_Disney "Disney" \
      "disneyplus.com,dssott.com,bamgrid.com,disney-plus.net" ""

    # 10. MaxHBO
    add_rule "$cfg" DN_MaxHBO "MaxHBO" \
      "max.com,hbomax.com,hbo.com,hbogo.com" ""

    # 11. PrimeVideo
    add_rule "$cfg" DN_PrimeVideo "PrimeVideo" \
      "primevideo.com,amazonvideo.com,aiv-cdn.net" ""

    # 12. Twitter
    add_rule "$cfg" DN_Twitter "Twitter" \
      "x.com,twitter.com,twimg.com,t.co" ""

    # 13. Telegram
    add_rule "$cfg" DN_Telegram "Telegram" \
      "telegram.org,t.me,telegram.me,telegra.ph" \
      "149.154.160.0/20,91.108.4.0/22,91.108.8.0/22,91.108.56.0/22"

    # 14. Google
    add_rule "$cfg" DN_Google "Google" \
      "google.com,gstatic.com,googleapis.com,googleusercontent.com,ggpht.com" ""

    # 15. TikTok
    add_rule "$cfg" DN_TikTok "TikTok" \
      "tiktok.com,tiktokcdn.com,tiktokv.com,byteoversea.com,ibytedtos.com,muscdn.com" ""

    # 16. PlayStation
    add_rule "$cfg" DN_PlayStation "PlayStation" \
      "playstation.com,playstation.net,sonyentertainmentnetwork.com" ""

    # 17. Nintendo
    add_rule "$cfg" DN_Nintendo "Nintendo" \
      "nintendo.com,nintendo.net,nintendo.co.jp" ""

    # 18. Instagram
    add_rule "$cfg" DN_Instagram "Instagram" \
      "instagram.com,cdninstagram.com" ""

    # 19. Signal
    add_rule "$cfg" DN_Signal "Signal" \
      "signal.org,signal.art,whispersystems.org" ""

    # 20. Spotify
    add_rule "$cfg" DN_Spotify "Spotify" \
      "spotify.com,scdn.co,spotifycdn.com" ""

    # 21. Slack
    add_rule "$cfg" DN_Slack "Slack" \
      "slack.com,slack-edge.com" ""

    # 22. DirectGame
    add_rule "$cfg" DN_DirectGame "DirectGame" "" ""

    # 23. ProxyGame
    add_rule "$cfg" DN_ProxyGame "ProxyGame" "" ""

    # 24. AIGC
    add_rule "$cfg" DN_AIGC "AIGC" "" ""

    # 25. Streaming
    add_rule "$cfg" DN_Streaming "Streaming" "" ""

    # 26. Proxy
    add_rule "$cfg" DN_Proxy "Proxy" "" ""

    # 27. Direct
    add_rule "$cfg" DN_Direct "Direct" "" ""

    # 28. LINE
    add_rule "$cfg" DN_LINE "LINE" \
      "line.me,line-apps.com,line-scdn.net,lin.ee,line.naver.jp" ""

    # 29. WhatsApp
    add_rule "$cfg" DN_WhatsApp "WhatsApp" \
      "whatsapp.com,whatsapp.net" ""

    # 30. Discord
    add_rule "$cfg" DN_Discord "Discord" \
      "discord.com,discord.gg,discordapp.com,discordapp.net,discordcdn.com" ""

    # 31. Facebook
    add_rule "$cfg" DN_Facebook "Facebook" \
      "facebook.com,fbcdn.net,fb.me,fbsbx.com,messenger.com" ""

    # 32. Reddit
    add_rule "$cfg" DN_Reddit "Reddit" \
      "reddit.com,redditmedia.com,redditstatic.com,redd.it" ""

    # 33. Claude
    add_rule "$cfg" DN_Claude "Claude" \
      "claude.ai,anthropic.com" ""

    # 34. Perplexity
    add_rule "$cfg" DN_Perplexity "Perplexity" \
      "perplexity.ai" ""

    # 35. Copilot
    add_rule "$cfg" DN_Copilot "Copilot" \
      "copilot.microsoft.com,copilot.cloud.microsoft" ""

    # 36. Grok
    add_rule "$cfg" DN_Grok "Grok" \
      "grok.com,x.ai" ""

    # 37. Apple
    add_rule "$cfg" DN_Apple "Apple" \
      "apple.com,icloud.com,apple-cloudkit.com,mzstatic.com" ""

    # 38. Microsoft
    add_rule "$cfg" DN_Microsoft "Microsoft" \
      "microsoft.com,live.com,office.com,office365.com,onedrive.com" ""

    # 39. Zoom
    add_rule "$cfg" DN_Zoom "Zoom" \
      "zoom.us,zoom.com" ""

    # 40. Notion
    add_rule "$cfg" DN_Notion "Notion" \
      "notion.so,notion.site,notionusercontent.com" ""

    # 41. Dropbox
    add_rule "$cfg" DN_Dropbox "Dropbox" \
      "dropbox.com,dropboxapi.com,dropboxusercontent.com" ""

    # 42. Xbox
    add_rule "$cfg" DN_Xbox "Xbox" \
      "xbox.com,xboxlive.com,xboxservices.com" ""

    # Migrate the old DoorNet2 R4Shunt node in place when present so
    # retained node selections survive.  New installs use DN_Shunt and
    # expose only the user-facing name “分流总节点”.
    if uci -q get "$cfg.DN_Shunt" >/dev/null 2>&1; then
        SHUNT_ID="DN_Shunt"
    elif uci -q get "$cfg.R4Shunt" >/dev/null 2>&1; then
        SHUNT_ID="R4Shunt"
        old_remarks="$(uci -q get "$cfg.$SHUNT_ID.remarks")"
        if [ -z "$old_remarks" ] || [ "$old_remarks" = "R4 分流总节点" ]; then
            uci -q set "$cfg.$SHUNT_ID.remarks=分流总节点"
        fi
    else
        SHUNT_ID="DN_Shunt"
        uci -q set "$cfg.$SHUNT_ID=nodes"
        uci -q set "$cfg.$SHUNT_ID.remarks=分流总节点"
        uci -q set "$cfg.$SHUNT_ID.type=Xray"
        uci -q set "$cfg.$SHUNT_ID.protocol=_shunt"
        uci -q set "$cfg.$SHUNT_ID.domainStrategy=IPOnDemand"
        uci -q set "$cfg.$SHUNT_ID.default_node=_direct"
    fi

    # On a clean install, make the preloaded shunt node the selected
    # main node while keeping the plugin itself disabled.  With its
    # default_node set to direct and ordinary preset rows unbound,
    # enabling the plugin before choosing proxy nodes remains safe.
    if [ "$RETAINED" = "0" ]; then
        if [ "$cfg" = "passwall" ]; then
            uci -q set passwall.@global[0].node="$SHUNT_ID"
        elif [ "$cfg" = "passwall2" ]; then
            uci -q set passwall2.@global[0].node="$SHUNT_ID"
            uci -q set "$cfg.$SHUNT_ID.domainMatcher=hybrid"
            uci -q set "$cfg.$SHUNT_ID.write_ipset_direct=1"
            uci -q set "$cfg.$SHUNT_ID.enable_geoview_ip=0"
        fi
    fi

    # Explicit direct bindings. WeChatTencent must remain direct
    # even if the shunt node's default route is later changed to proxy.
    for pair in \
        DN_WeChatTencent:_direct \
        DN_DirectGame:_direct \
        DN_Direct:_direct; do
        opt="${pair%%:*}"
        val="${pair#*:}"
        if [ "$RETAINED" = "0" ] || [ -z "$(uci -q get "$cfg.$SHUNT_ID.$opt")" ]; then
            uci -q set "$cfg.$SHUNT_ID.$opt=$val"
        fi
    done

    # Exact rule order requested by the user. Apply this strict order
    # on clean installs. On retained upgrades, add missing rules without
    # reordering or overwriting existing user choices.
    if [ "$RETAINED" = "0" ]; then
        RULE_ORDER="
    DN_WeChatTencent
    DN_ChatGPT_Login
    DN_OpenAI
    DN_GitHub
    DN_GoogleWork
    DN_GoogleAI
    DN_YouTube
    DN_Netflix
    DN_Disney
    DN_MaxHBO
    DN_PrimeVideo
    DN_Twitter
    DN_Telegram
    DN_Google
    DN_TikTok
    DN_PlayStation
    DN_Nintendo
    DN_Instagram
    DN_Signal
    DN_Spotify
    DN_Slack
    DN_DirectGame
    DN_ProxyGame
    DN_AIGC
    DN_Streaming
    DN_Proxy
    DN_Direct
    DN_LINE
    DN_WhatsApp
    DN_Discord
    DN_Facebook
    DN_Reddit
    DN_Claude
    DN_Perplexity
    DN_Copilot
    DN_Grok
    DN_Apple
    DN_Microsoft
    DN_Zoom
    DN_Notion
    DN_Dropbox
    DN_Xbox
    "
        pos=0
        for rule_id in $RULE_ORDER; do
            uci -q reorder "$cfg.$rule_id=$pos" >/dev/null 2>&1 || true
            pos=$((pos + 1))
        done
    fi

    uci -q commit "$cfg"
}

seed_config passwall
seed_config passwall2

touch "$PRESET_MARKER"
exit 0
EOF

chmod 755 files/etc/uci-defaults/zzza-doornet2-shunt-presets
sh -n files/etc/uci-defaults/zzza-doornet2-shunt-presets

# Preserve the one-time seed marker so online upgrades never replay
# the preset initializer over a user's later edits/selections.
if ! grep -qx '/etc/doornet2-shunt-presets-v2' \
    files/lib/upgrade/keep.d/doornet2-user-network-config; then
    echo '/etc/doornet2-shunt-presets-v2' \
      >> files/lib/upgrade/keep.d/doornet2-user-network-config
fi

echo "===== SHUNT PRESET POLICY ====="
echo "PassWall:  preloaded 分流总节点, plugin still default OFF"
echo "PassWall2: preloaded 分流总节点, plugin still default OFF"
echo "First-boot order: PassWall package defaults -> shunt presets -> OFF-state initializer"
echo "Proxy service rules have no baked-in personal node IDs."
echo "WeChatTencent is rule #1 and is explicitly default DIRECT in PassWall and PassWall2."
echo "Rule order is identical in PassWall and PassWall2: WeChatTencent ... Xbox (42 rules)."
echo "UU-specific domains are not present."
