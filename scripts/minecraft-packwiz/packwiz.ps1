# Minecraft: Packwiz helper for AMP3 (Windows).
#   install <server folder> <pack url>         Reads [versions] from the pack's pack.toml and installs the
#                                               matching server as server.jar (Vanilla, or Fabric).
#   sync    <server folder> <pack url> [java]  Installs/updates the pack with packwiz-installer
#                                               (server-side mods only).
param([string]$Mode, [string]$Base, [string]$Url, [string]$Java = '')
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if (-not (Test-Path -LiteralPath $Base)) { Write-Host "Server folder not found: $Base"; exit 1 }
Set-Location -LiteralPath $Base

# A GitHub page link (github.com/<owner>/<repo>/blob/<branch>/<path>) becomes the raw file link.
$Url = $Url -replace '^https?://github\.com/([^/]+)/([^/]+)/blob/', 'https://raw.githubusercontent.com/$1/$2/'

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
        if ($v['quilt'] -or $v['forge'] -or $v['neoforge']) {
            Write-Host "This pack needs a mod loader the template does not install yet (quilt=$($v['quilt']) forge=$($v['forge']) neoforge=$($v['neoforge']))."
            exit 1
        }
        try {
            if ($v['fabric']) {
                # Store the array first: Windows PowerShell passes an Invoke-RestMethod array down a pipeline as ONE object.
                $installers = Invoke-RestMethod -Uri 'https://meta.fabricmc.net/v2/versions/installer'
                $installer = ($installers | Where-Object { $_.stable } | Select-Object -First 1).version
                if (-not $installer) { Write-Host 'Could not read the Fabric installer version.'; exit 1 }
                $jar = "https://meta.fabricmc.net/v2/versions/loader/$mc/$($v['fabric'])/$installer/server/jar"
                $what = "Fabric $($v['fabric'])"
            } else {
                $entry = (Invoke-RestMethod -Uri 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json').versions | Where-Object { $_.id -eq $mc } | Select-Object -First 1
                if (-not $entry) { Write-Host "Minecraft $mc was not found in Mojang's version list."; exit 1 }
                $jar = (Invoke-RestMethod -Uri $entry.url).downloads.server.url
                if (-not $jar) { Write-Host "Minecraft $mc has no server download."; exit 1 }
                $what = 'Vanilla'
            }
            Invoke-WebRequest -UseBasicParsing -Uri $jar -OutFile 'server.jar.part'
            Move-Item -Force -LiteralPath 'server.jar.part' -Destination 'server.jar'
        } catch {
            Remove-Item -Force -ErrorAction SilentlyContinue -LiteralPath 'server.jar.part'
            Write-Host "Could not install the server: $($_.Exception.Message)"; exit 1
        }
        Write-Host "Installed the $what server for Minecraft $mc."
    }
    'sync' {
        if (-not $Java -or -not (Test-Path -LiteralPath $Java)) { $Java = 'java' }
        & $Java -cp 'packwiz-installer/packwiz-installer.jar' link.infra.packwiz.installer.Main -g -s server --pack-folder . $Url
        exit $LASTEXITCODE
    }
    default { Write-Host 'Usage: packwiz.ps1 install|sync <server folder> <pack url> [java]'; exit 2 }
}
