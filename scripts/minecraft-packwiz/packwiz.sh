#!/bin/bash
# Minecraft: Packwiz helper for AMP3 (Linux).
#   install <server folder> <pack url> [java path]
#       Reads [versions] from the pack's pack.toml, installs the matching server as server.jar
#       (Vanilla, Fabric, Forge 1.17+ or NeoForge) and notes the Java version Mojang requires.
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
    if [ -n "$QUILT" ]; then
        echo "This pack uses Quilt $QUILT, which this template does not install yet (Vanilla, Fabric, Forge and NeoForge for now)."
        exit 1
    fi
    # Mojang's data for this Minecraft version: server download and required Java.
    INFO=$(get https://piston-meta.mojang.com/mc/game/version_manifest_v2.json | tr -d '\r\n' | grep -o '{[^{}]*}' \
        | grep "\"id\": *\"$MC\"" | head -n 1 | grep -o '"url": *"[^"]*"' | cut -d'"' -f4)
    [ -n "$INFO" ] || { echo "Minecraft $MC was not found in Mojang's version list."; exit 1; }
    VJSON=$(get "$INFO" | tr -d '\r\n')
    NEEDJAVA=$(printf '%s' "$VJSON" | grep -o '"javaVersion": *{[^{}]*}' | grep -o '"majorVersion": *[0-9]*' | grep -o '[0-9]*$')
    [ "$NEEDJAVA" = "16" ] && NEEDJAVA=17   # Minecraft 1.17 asks for Java 16; 17 is the nearest version offered

    # Forge/NeoForge: their installer sets the server up (run.sh + libraries); NeoForge's ServerStarterJar is then
    # server.jar, which starts that setup with a plain "java -jar server.jar" (Forge 1.17+, all NeoForge).
    STARTER="https://github.com/neoforged/ServerStarterJar/releases/latest/download/server.jar"
    INSTJAR=""; JAR=""
    if [ -n "$NEOFORGE" ]; then
        case "$MC" in
            1.20.1) INSTJAR="https://maven.neoforged.net/releases/net/neoforged/forge/1.20.1-$NEOFORGE/forge-1.20.1-$NEOFORGE-installer.jar" ;;
            *)      INSTJAR="https://maven.neoforged.net/releases/net/neoforged/neoforge/$NEOFORGE/neoforge-$NEOFORGE-installer.jar" ;;
        esac
        LOADER="neoforge $NEOFORGE"; WHAT="NeoForge $NEOFORGE"
    elif [ -n "$FORGE" ]; then
        MINOR=$(printf '%s' "$MC" | sed -nE 's/^1\.([0-9]+).*/\1/p')
        if [ -n "$MINOR" ] && [ "$MINOR" -lt 17 ]; then
            echo "This pack uses Forge for Minecraft $MC. Forge before Minecraft 1.17 is not supported yet."
            exit 1
        fi
        case "$FORGE" in "$MC"-*) FV="$FORGE" ;; *) FV="$MC-$FORGE" ;; esac
        INSTJAR="https://maven.minecraftforge.net/net/minecraftforge/forge/$FV/forge-$FV-installer.jar"
        LOADER="forge $FV"; WHAT="Forge $FORGE"
    elif [ -n "$FABRIC" ]; then
        INSTALLER=$(get https://meta.fabricmc.net/v2/versions/installer | tr -d ' \r\n' | grep -o '{[^{}]*}' \
            | grep '"stable":true' | head -n 1 | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        [ -n "$INSTALLER" ] || { echo "Could not read the Fabric installer version."; exit 1; }
        JAR="https://meta.fabricmc.net/v2/versions/loader/$MC/$FABRIC/$INSTALLER/server/jar"
        LOADER="fabric $FABRIC"; WHAT="Fabric $FABRIC"
    else
        JAR=$(printf '%s' "$VJSON" | grep -o '"server": *{[^{}]*}' | grep -o '"url": *"[^"]*"' | cut -d'"' -f4)
        [ -n "$JAR" ] || { echo "Minecraft $MC has no server download."; exit 1; }
        LOADER="vanilla"; WHAT="Vanilla"
    fi
    if [ -n "$INSTJAR" ]; then
        OLDLOADER=$(sed -n 's/^loader=//p' "$INFOFILE" 2>/dev/null | head -n 1)
        if [ "$OLDLOADER" = "$LOADER" ] && [ -f server.jar ] && { [ -f run.sh ] || [ -f run.bat ]; }; then
            echo "$WHAT for Minecraft $MC is already installed."
        else
            { [ -n "$JAVA" ] && [ -x "$JAVA" ]; } || JAVA=java
            echo "Running the $WHAT installer, this can take a few minutes..."
            if ! { get "$INSTJAR" > loader-installer.jar && [ -s loader-installer.jar ]; }; then
                rm -f loader-installer.jar; echo "Could not download the installer: $INSTJAR"; exit 1
            fi
            if ! "$JAVA" -jar loader-installer.jar --installServer .; then
                rm -f loader-installer.jar; echo "The $WHAT installer failed (see above)."; exit 1
            fi
            rm -f loader-installer.jar loader-installer.jar.log installer.log
            if [ ! -f run.sh ] && [ ! -f run.bat ]; then
                echo "The $WHAT installer did not create run.sh, so the server starter cannot use it."
                exit 1
            fi
            JAR="$STARTER"
        fi
    fi
    if [ -n "$JAR" ]; then
        if get "$JAR" > server.jar.part && [ -s server.jar.part ]; then
            mv -f server.jar.part server.jar
        else
            rm -f server.jar.part; echo "Could not download the server: $JAR"; exit 1
        fi
        echo "Installed the $WHAT server for Minecraft $MC."
    fi
    mkdir -p packwiz-installer
    printf 'minecraft=%s\njava=%s\nloader=%s\n' "$MC" "$NEEDJAVA" "$LOADER" > "$INFOFILE"
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
