#!/bin/bash
# Minecraft: Packwiz helper for AMP3 (Linux).
#   install <server folder> <pack url>
#       Reads [versions] from the pack's pack.toml, installs the matching server as server.jar
#       (Vanilla, or Fabric) and notes the Java version Mojang requires for that Minecraft version.
#   sync <server folder> <pack url> [java path] [java version setting]
#       Warns when the selected Java does not match the pack, then installs/updates the pack with
#       packwiz-installer (server-side mods only).
MODE="$1"; BASE="$2"; URL="$3"; JAVA="$4"; JAVASETTING="$5"
cd "$BASE" || { echo "Server folder not found: $BASE"; exit 1; }
INFOFILE="packwiz-installer/pack-versions.txt"

# A GitHub page or folder link (github.com/<owner>/<repo>/blob|tree/<branch>/<path>) becomes the raw link,
# and a link to the pack's folder gets pack.toml added.
URL=$(printf '%s' "$URL" | sed -E 's#^https?://github\.com/([^/]+)/([^/]+)/(blob|tree)/#https://raw.githubusercontent.com/\1/\2/#')
case "$URL" in *.toml) ;; *) URL="${URL%/}/pack.toml" ;; esac

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
    # Mojang's data for this Minecraft version: server download and required Java.
    INFO=$(get https://piston-meta.mojang.com/mc/game/version_manifest_v2.json | tr -d '\r\n' | grep -o '{[^{}]*}' \
        | grep "\"id\": *\"$MC\"" | head -n 1 | grep -o '"url": *"[^"]*"' | cut -d'"' -f4)
    [ -n "$INFO" ] || { echo "Minecraft $MC was not found in Mojang's version list."; exit 1; }
    VJSON=$(get "$INFO" | tr -d '\r\n')
    NEEDJAVA=$(printf '%s' "$VJSON" | grep -o '"javaVersion": *{[^{}]*}' | grep -o '"majorVersion": *[0-9]*' | grep -o '[0-9]*$')
    [ "$NEEDJAVA" = "16" ] && NEEDJAVA=17   # Minecraft 1.17 asks for Java 16; 17 is the nearest version offered
    if [ -n "$FABRIC" ]; then
        INSTALLER=$(get https://meta.fabricmc.net/v2/versions/installer | tr -d ' \r\n' | grep -o '{[^{}]*}' \
            | grep '"stable":true' | head -n 1 | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        [ -n "$INSTALLER" ] || { echo "Could not read the Fabric installer version."; exit 1; }
        JAR="https://meta.fabricmc.net/v2/versions/loader/$MC/$FABRIC/$INSTALLER/server/jar"
        WHAT="Fabric $FABRIC"
    else
        JAR=$(printf '%s' "$VJSON" | grep -o '"server": *{[^{}]*}' | grep -o '"url": *"[^"]*"' | cut -d'"' -f4)
        [ -n "$JAR" ] || { echo "Minecraft $MC has no server download."; exit 1; }
        WHAT="Vanilla"
    fi
    if get "$JAR" > server.jar.part && [ -s server.jar.part ]; then
        mv -f server.jar.part server.jar
    else
        rm -f server.jar.part; echo "Could not download the server: $JAR"; exit 1
    fi
    echo "Installed the $WHAT server for Minecraft $MC."
    mkdir -p packwiz-installer
    printf 'minecraft=%s\njava=%s\n' "$MC" "$NEEDJAVA" > "$INFOFILE"
    [ -n "$NEEDJAVA" ] && echo "Minecraft $MC needs Java $NEEDJAVA (Mojang). Set the Java version to match if the server does not start."
    ;;
sync)
    # Java check: compare the selected Java with what the pack's Minecraft version needs. Warns only.
    NEEDJAVA=$(sed -n 's/^java=//p' "$INFOFILE" 2>/dev/null | head -n 1)
    PACKMC=$(sed -n 's/^minecraft=//p' "$INFOFILE" 2>/dev/null | head -n 1)
    HAVE=""
    if [ -n "$JAVA" ] && [ -x "$JAVA" ]; then
        HAVE=$("$JAVA" -version 2>&1 | grep -o 'version "[^"]*"' | head -n 1 | cut -d'"' -f2)
        case "$HAVE" in 1.*) HAVE=$(printf '%s' "$HAVE" | cut -d. -f2) ;; *) HAVE=${HAVE%%[.+-]*} ;; esac
    else
        case "$JAVASETTING" in ''|*[!0-9]*) ;; *) HAVE="$JAVASETTING" ;; esac
    fi
    if [ -n "$NEEDJAVA" ] && [ -n "$HAVE" ] && [ "$HAVE" != "$NEEDJAVA" ]; then
        if [ "$HAVE" -lt "$NEEDJAVA" ]; then
            echo "WARNING: this pack is for Minecraft $PACKMC, which needs Java $NEEDJAVA or newer, but Java $HAVE is selected. Set the Java version to $NEEDJAVA."
        else
            echo "WARNING: this pack is for Minecraft $PACKMC, made for Java $NEEDJAVA, but Java $HAVE is selected. If the server fails with \"Unsupported class file major version\", set the Java version to $NEEDJAVA."
        fi
    fi
    { [ -n "$JAVA" ] && [ -x "$JAVA" ]; } || JAVA=java
    exec "$JAVA" -cp packwiz-installer/packwiz-installer.jar link.infra.packwiz.installer.Main -g -s server --pack-folder . "$URL"
    ;;
*)
    echo "Usage: packwiz.sh install|sync <server folder> <pack url> [java path] [java version setting]"
    exit 2
    ;;
esac
