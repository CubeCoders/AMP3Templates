# Minecraft: Packwiz helper for AMP3 (Windows).
#   install <server folder> <pack url> [java path]
#       Reads [versions] from the pack's pack.toml, installs the matching server as server.jar
#       (Vanilla, Fabric, Forge 1.17+ or NeoForge) and notes the Java version Mojang requires.
#   sync <server folder> <pack url> [java path] [java version setting]
#       Warns when the selected Java does not match the pack, then installs/updates the pack with
#       packwiz-installer (server-side mods only).
param([string]$Mode, [string]$Base, [string]$Url, [string]$Java = '', [string]$JavaSetting = '')
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if (-not (Test-Path -LiteralPath $Base)) { Write-Host "Server folder not found: $Base"; exit 1 }
Set-Location -LiteralPath $Base
$InfoFile = 'packwiz-installer\pack-versions.txt'

# A GitHub page or folder link (github.com/<owner>/<repo>/blob|tree/<branch>/<path>) becomes the raw link,
# and a link to the pack's folder gets pack.toml added.
$Url = $Url -replace '^https?://github\.com/([^/]+)/([^/]+)/(blob|tree)/', 'https://raw.githubusercontent.com/$1/$2/'
if ($Url -notmatch '\.toml$') { $Url = $Url.TrimEnd('/') + '/pack.toml' }

switch ($Mode) {
    'install' {
        try {
            $toml = (Invoke-WebRequest -UseBasicParsing -Uri $Url).Content
            if ($toml -is [byte[]]) { $toml = [Text.Encoding]::UTF8.GetString($toml) }
        } catch { Write-Host "Could not download the pack file: $Url"; exit 1 }
        $section = ''; $v = @{}
        foreach ($line in ($toml -split "`r?`n")) {
            if ($line -match '^\s*\[([^\]]+)\]\s*$') { $section = $Matches[1].Trim(); continue }
            if ($section -eq 'versions' -and $line -match '^\s*([\w-]+)\s*=\s*["'']([^"'']+)["'']') { $v[$Matches[1]] = $Matches[2] }
        }
        $mc = $v['minecraft']
        if (-not $mc) { Write-Host 'The pack file has no Minecraft version ([versions] minecraft). Is the Pack URL the raw pack.toml link?'; exit 1 }
        if ($v['quilt']) {
            Write-Host "This pack uses Quilt $($v['quilt']), which this template does not install yet (Vanilla, Fabric, Forge and NeoForge for now)."
            exit 1
        }
        # Forge/NeoForge: their installer sets the server up (run.bat + libraries); NeoForge's ServerStarterJar is then
        # server.jar, which starts that setup with a plain "java -jar server.jar" (Forge 1.17+, all NeoForge).
        $starter = 'https://github.com/neoforged/ServerStarterJar/releases/latest/download/server.jar'
        try {
            # Mojang's data for this Minecraft version: server download and required Java.
            # Store arrays in variables first: Windows PowerShell passes an Invoke-RestMethod array down a pipeline as ONE object.
            $manifest = Invoke-RestMethod -Uri 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
            $entry = $manifest.versions | Where-Object { $_.id -eq $mc } | Select-Object -First 1
            if (-not $entry) { Write-Host "Minecraft $mc was not found in Mojang's version list."; exit 1 }
            $vjson = Invoke-RestMethod -Uri $entry.url
            $needJava = [string]$vjson.javaVersion.majorVersion
            if ($needJava -eq '16') { $needJava = '17' }   # Minecraft 1.17 asks for Java 16; 17 is the nearest version offered
            $instJar = ''; $jar = ''
            if ($v['neoforge']) {
                $nf = $v['neoforge']
                if ($mc -eq '1.20.1') { $instJar = "https://maven.neoforged.net/releases/net/neoforged/forge/1.20.1-$nf/forge-1.20.1-$nf-installer.jar" }
                else { $instJar = "https://maven.neoforged.net/releases/net/neoforged/neoforge/$nf/neoforge-$nf-installer.jar" }
                $loader = "neoforge $nf"; $what = "NeoForge $nf"
            } elseif ($v['forge']) {
                if ($mc -match '^1\.(\d+)' -and [int]$Matches[1] -lt 17) {
                    Write-Host "This pack uses Forge for Minecraft $mc. Forge before Minecraft 1.17 is not supported yet."; exit 1
                }
                $fv = $v['forge']; if (-not $fv.StartsWith("$mc-")) { $fv = "$mc-$fv" }
                $instJar = "https://maven.minecraftforge.net/net/minecraftforge/forge/$fv/forge-$fv-installer.jar"
                $loader = "forge $fv"; $what = "Forge $($v['forge'])"
            } elseif ($v['fabric']) {
                $installers = Invoke-RestMethod -Uri 'https://meta.fabricmc.net/v2/versions/installer'
                $installer = ($installers | Where-Object { $_.stable } | Select-Object -First 1).version
                if (-not $installer) { Write-Host 'Could not read the Fabric installer version.'; exit 1 }
                $jar = "https://meta.fabricmc.net/v2/versions/loader/$mc/$($v['fabric'])/$installer/server/jar"
                $loader = "fabric $($v['fabric'])"; $what = "Fabric $($v['fabric'])"
            } else {
                $jar = $vjson.downloads.server.url
                if (-not $jar) { Write-Host "Minecraft $mc has no server download."; exit 1 }
                $loader = 'vanilla'; $what = 'Vanilla'
            }
            if ($instJar) {
                $oldLoader = ''
                if (Test-Path -LiteralPath $InfoFile) {
                    foreach ($line in Get-Content -LiteralPath $InfoFile) { if ($line -match '^loader=(.+)$') { $oldLoader = $Matches[1] } }
                }
                if ($oldLoader -eq $loader -and (Test-Path 'server.jar') -and ((Test-Path 'run.bat') -or (Test-Path 'run.sh'))) {
                    Write-Host "$what for Minecraft $mc is already installed."
                } else {
                    $javaExe = $Java; if (-not $javaExe -or -not (Test-Path -LiteralPath $javaExe)) { $javaExe = 'java' }
                    Write-Host "Running the $what installer, this can take a few minutes..."
                    Invoke-WebRequest -UseBasicParsing -Uri $instJar -OutFile 'loader-installer.jar'
                    & $javaExe -jar 'loader-installer.jar' --installServer .
                    $code = $LASTEXITCODE
                    Remove-Item -Force -ErrorAction SilentlyContinue 'loader-installer.jar', 'loader-installer.jar.log', 'installer.log'
                    if ($code -ne 0) { Write-Host "The $what installer failed (see above)."; exit 1 }
                    if (-not (Test-Path 'run.bat') -and -not (Test-Path 'run.sh')) {
                        Write-Host "The $what installer did not create run.bat, so the server starter cannot use it."; exit 1
                    }
                    $jar = $starter
                }
            }
            if ($jar) {
                Invoke-WebRequest -UseBasicParsing -Uri $jar -OutFile 'server.jar.part'
                Move-Item -Force -LiteralPath 'server.jar.part' -Destination 'server.jar'
                Write-Host "Installed the $what server for Minecraft $mc."
            }
        } catch {
            Remove-Item -Force -ErrorAction SilentlyContinue -LiteralPath 'server.jar.part', 'loader-installer.jar'
            Write-Host "Could not install the server: $($_.Exception.Message)"; exit 1
        }
        New-Item -ItemType Directory -Force 'packwiz-installer' | Out-Null
        Set-Content -LiteralPath $InfoFile -Value @("minecraft=$mc", "java=$needJava", "loader=$loader") -Encoding ASCII
        if ($needJava) { Write-Host "Minecraft $mc needs Java $needJava (Mojang). Set the Java version to match if the server does not start." }
    }
    'sync' {
        # Java check: compare the selected Java with what the pack's Minecraft version needs. Warns only.
        $needJava = ''; $packMc = ''
        if (Test-Path -LiteralPath $InfoFile) {
            foreach ($line in Get-Content -LiteralPath $InfoFile) {
                if ($line -match '^java=(\d+)') { $needJava = $Matches[1] }
                if ($line -match '^minecraft=(.+)$') { $packMc = $Matches[1] }
            }
        }
        $have = ''
        if ($Java -and (Test-Path -LiteralPath $Java)) {
            $out = (& $Java -version 2>&1 | Out-String)
            if ($out -match 'version "1\.(\d+)') { $have = $Matches[1] } elseif ($out -match 'version "(\d+)') { $have = $Matches[1] }
        } elseif ($JavaSetting -match '^\d+$') { $have = $JavaSetting }
        if ($needJava -and $have -and ($have -ne $needJava)) {
            if ([int]$have -lt [int]$needJava) {
                Write-Host "WARNING: this pack is for Minecraft $packMc, which needs Java $needJava or newer, but Java $have is selected. Set the Java version to $needJava."
            } else {
                Write-Host "WARNING: this pack is for Minecraft $packMc, made for Java $needJava, but Java $have is selected. If the server fails with `"Unsupported class file major version`", set the Java version to $needJava."
            }
        }
        if (-not $Java -or -not (Test-Path -LiteralPath $Java)) { $Java = 'java' }
        & $Java -cp 'packwiz-installer/packwiz-installer.jar' link.infra.packwiz.installer.Main -g -s server --pack-folder . $Url
        exit $LASTEXITCODE
    }
    default { Write-Host 'Usage: packwiz.ps1 install|sync <server folder> <pack url> [java path] [java version setting]'; exit 2 }
}
