#!/usr/bin/env bash
# Migrated from V1.7 workflow step 30: Add taskd compatibility fix
set -e

mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-taskd-compat <<'EOF'
#!/bin/sh

TASKS="/etc/init.d/tasks"

if [ -f "$TASKS" ] && \
   grep -q 'extra_command ' "$TASKS" && \
   ! grep -q 'TASKD_EXTRA_COMMAND_COMPAT' "$TASKS"
then

    TMP="/tmp/tasks.compat.$$"

    awk '
    NR == 1 {
        print
        print ""
        print "# TASKD_EXTRA_COMMAND_COMPAT"
        print "type extra_command >/dev/null 2>&1 || extra_command() { :; }"
        next
    }
    {
        print
    }
    ' "$TASKS" > "$TMP"

    cat "$TMP" > "$TASKS"
    rm -f "$TMP"

    chmod 755 "$TASKS"
fi

exit 0
EOF

chmod 755 files/etc/uci-defaults/99-taskd-compat
