#!/bin/sh
# Manage the PiGallery2 launchd agent -- the native equivalent of the compose
# file's `restart: unless-stopped`. The agent starts at login and is restarted
# if it crashes.
#
#   service.sh install     write the agent plist and start it
#   service.sh uninstall   stop it and remove the plist
#   service.sh restart     restart (needed after editing config.macos.json)
#   service.sh status      show launchd's view of the job
#   service.sh logs        follow the log
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)

LABEL=local.pigallery2
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
LOG=$HOME/Library/Logs/pigallery2/pigallery2.log
DOMAIN=gui/$(id -u)

write_plist() {
    mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>$REPO/scripts/macos/run.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
EOF
}

case "${1:-}" in
    install)
        launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
        write_plist
        launchctl bootstrap "$DOMAIN" "$PLIST"
        echo "Started $LABEL -- http://localhost:8082, log: $LOG"
        ;;
    uninstall)
        launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
        rm -f "$PLIST"
        echo "Removed $LABEL"
        ;;
    restart)
        launchctl kickstart -k "$DOMAIN/$LABEL"
        ;;
    status)
        launchctl print "$DOMAIN/$LABEL" | grep -E '^[[:space:]]*(state|pid|last exit code|runs) ='
        ;;
    logs)
        tail -f "$LOG"
        ;;
    *)
        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
