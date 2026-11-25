#!/bin/bash
# Minecraft: Packwiz helper for AMP3 (Linux).
#   install <server folder> <pack url>         Reads [versions] from the pack's pack.toml and installs the
#                                               matching server as server.jar (Vanilla, or Fabric).
#   sync    <server folder> <pack url> [java]  Installs/updates the pack with packwiz-installer
#                                               (server-side mods only).
MODE="$1"; BASE="$2"; URL="$3"; JAVA="$4"
cd "$BASE" || { echo "Server folder not found: $BASE"; exit 1; }

# A GitHub page link (github.com/<owner>/<repo>/blob/<branch>/<path>) becomes the raw file link.
URL=$(printf '%s' "$URL" | sed -E 's#^https?://github\.com/([^/]+)/([^/]+)/blob/#https://raw.githubusercontent.com/\1/\2/#')

get() { curl -fsSL --retry 2 "$1" 2>/dev/null || wget -qO- "$1" 2>/dev/null; }

case "$MODE" in
install)
    TOML=$(get "$URL") || { echo "Could not download the pack file: $URL"; exit 1; }
    ver() {
        printf '%s\n' "$TOML" | tr -d '\r' | sed -n '/^\[versions\]/,/^\[/p' \
            | sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"'].*/\1/p" | head -n 1
    }
    MC=$(ver minecraft); FABRIC=$(ver fabric); QUILT=$(ver quilt); FORGE=$(ver forge); NEOFORGE=$(ver neoforge)
    if [ -z "$MC" ]; then
        echo "The pack file has no Minecraft version ([versions] minecraft). Is the Pack URL the raw pack.toml link?"
        exit 1
    fi
    if [ -n "$QUILT$FORGE$NEOFORGE" ]; then
        echo "This pack needs a mod loader the template does not install yet (quilt=$QUILT forge=$FORGE neoforge=$NEOFORGE)."
        exit 1
    fi
    if [ -n "$FABRIC" ]; then
        INSTALLER=$(get https://meta.fabricmc.net/v2/versions/installer | tr -d ' \r\n' | grep -o '{[^{}]*}' \
            | grep '"stable":true' | head -n 1 | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        [ -n "$INSTALLER" ] || { echo "Could not read the Fabric installer version."; exit 1; }
        JAR="https://meta.fabricmc.net/v2/versions/loader/$MC/$FABRIC/$INSTALLER/server/jar"
        WHAT="Fabric $FABRIC"
    else
        INFO=$(get https://piston-meta.mojang.com/mc/game/version_manifest_v2.json | tr -d '\r\n' | grep -o '{[^{}]*}' \
            | grep "\"id\": *\"$MC\"" | head -n 1 | grep -o '"url": *"[^"]*"' | cut -d'"' -f4)
        [ -n "$INFO" ] || { echo "Minecraft $MC was not found in Mojang's version list."; exit 1; }
        JAR=$(get "$INFO" | tr -d '\r\n' | grep -o '"server": *{[^{}]*}' | grep -o '"url": *"[^"]*"' | cut -d'"' -f4)
        [ -n "$JAR" ] || { echo "Minecraft $MC has no server download."; exit 1; }
        WHAT="Vanilla"
    fi
    if get "$JAR" > server.jar.part && [ -s server.jar.part ]; then
        mv -f server.jar.part server.jar
    else
        rm -f server.jar.part; echo "Could not download the server: $JAR"; exit 1
    fi
    echo "Installed the $WHAT server for Minecraft $MC."
    ;;
sync)
    { [ -n "$JAVA" ] && [ -x "$JAVA" ]; } || JAVA=java
    exec "$JAVA" -cp packwiz-installer/packwiz-installer.jar link.infra.packwiz.installer.Main -g -s server --pack-folder . "$URL"
    ;;
*)
    echo "Usage: packwiz.sh install|sync <server folder> <pack url> [java]"
    exit 2
    ;;
esac
