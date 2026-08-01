param(
    [switch]$Release = $true
)

$ErrorActionPreference = "Stop"
$serverDir = $PSScriptRoot

# ── Helper: read .metadata.json from a folder ──
function Read-Metadata($folderPath) {
    $metaFile = Join-Path $folderPath ".metadata.json"
    if (Test-Path $metaFile) {
        try {
            $content = Get-Content $metaFile -Raw -Encoding UTF8
            $json = $content | ConvertFrom-Json
            $map = @{}
            foreach ($m in $json.mods) {
                $map[$m.file] = $m
            }
            return $map
        } catch {
            Write-Warning "Failed to read $metaFile : $_"
            return @{}
        }
    }
    return @{}
}

# ── Helper: determine category from relative path ──
function Get-Category($relPath) {
    if ($relPath.StartsWith("mods/")) { return "mod" }
    elseif ($relPath.StartsWith("optional_mods/")) { return "mod" }
    elseif ($relPath.StartsWith("config/")) { return "config" }
    elseif ($relPath.StartsWith("shaderpacks/")) { return "shader" }
    elseif ($relPath.StartsWith("resourcepacks/")) { return "resourcepack" }
    elseif ($relPath.StartsWith("libraries/")) { return "library" }
    elseif ($relPath.StartsWith("tacz/")) { return "game" }
    elseif ($relPath.StartsWith("pointblank/")) { return "game" }
    else { return "game" }
}

# ── Helper: get mod name from data or filename ──
function Get-ModName($relPath, $metadataMap) {
    $fileName = Split-Path $relPath -Leaf
    if ($metadataMap.ContainsKey($fileName) -and $metadataMap[$fileName].mod_name) {
        return $metadataMap[$fileName].mod_name
    }
    # Try filename without extension
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    # Clean up common suffixes for readability
    $clean = $baseName -replace '-(forge|fabric|Forge|Fabric)-?\d.*', ''
    $clean = $clean -replace '-?\d+\.\d+\.\d+.*', ''
    $clean = $clean -replace '[-_]', ' '
    $clean = $clean.Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = $baseName }
    return $clean
}

# ── Helper: get description from metadata ──
function Get-Description($relPath, $metadataMap) {
    $fileName = Split-Path $relPath -Leaf
    if ($metadataMap.ContainsKey($fileName) -and $metadataMap[$fileName].mod_description) {
        return $metadataMap[$fileName].mod_description
    }
    return ""
}

# ── Helper: check if optional ──
function Is-Optional($relPath) {
    return $relPath.StartsWith("optional_mods/") -or $relPath.StartsWith("shaderpacks/") -or $relPath.StartsWith("resourcepacks/")
}

# ── Helper: default_enabled from metadata ──
function Get-DefaultEnabled($relPath, $metadataMap) {
    $fileName = Split-Path $relPath -Leaf
    if ($metadataMap.ContainsKey($fileName) -and $metadataMap[$fileName].default_enabled -eq $true) {
        return $true
    }
    return $false
}

# ── Helper: icon_url from metadata ──
function Get-IconUrl($relPath, $metadataMap) {
    $fileName = Split-Path $relPath -Leaf
    if ($metadataMap.ContainsKey($fileName) -and $metadataMap[$fileName].icon_url) {
        return $metadataMap[$fileName].icon_url
    }
    return $null
}

# ── Main ──
Write-Host "=== Manifest Generator ===" -ForegroundColor Cyan
Write-Host "Scanning: $serverDir" -ForegroundColor Gray

# Collect all files
$files = Get-ChildItem -LiteralPath $serverDir -Recurse -File | Where-Object {
    $fn = $_.FullName
    $fn -notlike "*\.git\*" -and
    $fn -notlike "*\gen.ps1" -and
    $fn -notlike "*\manifest_seed.sql" -and
    $fn -notlike "*\manifest.json" -and
    $fn -notlike "*\.metadata.json" -and
    $fn -notlike "*\.connector\*" -and
    $fn -notlike "*\.index\*" -and
    $fn -notlike "*\anticheat\*" -and
    $fn -notlike "*.sig" -and
    $fn -notlike "*.log" -and
    $fn -notlike "*.lock"
}

# Read metadata from optional folders
$optionalMeta = Read-Metadata (Join-Path $serverDir "optional_mods")
$shaderMeta = Read-Metadata (Join-Path $serverDir "shaderpacks")
$resourceMeta = Read-Metadata (Join-Path $serverDir "resourcepacks")

# Merge metadata maps
$allMeta = @{}
$optionalMeta.GetEnumerator() | ForEach-Object { $allMeta[$_.Key] = $_.Value }
$shaderMeta.GetEnumerator() | ForEach-Object { $allMeta[$_.Key] = $_.Value }
$resourceMeta.GetEnumerator() | ForEach-Object { $allMeta[$_.Key] = $_.Value }

$jsonFiles = @()

foreach ($f in $files) {
    $rel = $f.FullName.Substring($serverDir.Length + 1).Replace("\", "/")
    $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()

    $isOpt = $false; if (Is-Optional $rel) { $isOpt = $true }

    $entry = @{
        path = $rel
        size = $f.Length
        sha256 = $hash
        category = Get-Category $rel
        mod_name = Get-ModName $rel $allMeta
        mod_description = Get-Description $rel $allMeta
        mod_optional = $isOpt
        default_enabled = Get-DefaultEnabled $rel $allMeta
    }

    $iconUrl = Get-IconUrl $rel $allMeta
    if ($iconUrl) { $entry.icon_url = $iconUrl }

    $jsonFiles += $entry
}

# Also generate SQL seed for server
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("TRUNCATE pwp_core.file_manifests;")
$header = "INSERT INTO file_manifests (file_path,file_size,sha256,version,category,mod_name,mod_description,mod_optional) VALUES"
$batchSize = 500

for ($i = 0; $i -lt $files.Count; $i += $batchSize) {
    $batch = $files[$i..[Math]::Min($i + $batchSize - 1, $files.Count - 1)]
    [void]$sb.AppendLine($header)
    for ($j = 0; $j -lt $batch.Count; $j++) {
        $f = $batch[$j]
        $rel = $f.FullName.Substring($serverDir.Length + 1).Replace("\", "/")
        $cat = Get-Category $rel
        $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
        $epath = $rel -replace "'", "''"
        $modName = Get-ModName $rel $allMeta
        $isOpt = "FALSE"; if (Is-Optional $rel) { $isOpt = "TRUE" }
        $modNameSql = if ($modName) { "'$modName'" } else { "NULL" }
        $comma = if ($j -eq $batch.Count - 1) { ";" } else { "," }
        [void]$sb.AppendLine("('$epath', $($f.Length), '$hash', 'latest', '$cat', $modNameSql, NULL, $isOpt)$comma")
    }
}

$sqlOutput = Join-Path $serverDir "manifest_seed.sql"
$sb.ToString() | Out-File -LiteralPath $sqlOutput -Encoding UTF8
Write-Output "SQL seed: $sqlOutput ($($files.Count) files)"

# Write JSON manifest
$jsonOutput = @{ files = $jsonFiles } | ConvertTo-Json -Compress -Depth 10
$jsonPath = Join-Path $serverDir "manifest.json"
[System.IO.File]::WriteAllText($jsonPath, $jsonOutput, [System.Text.UTF8Encoding]::new($false))
Write-Output "JSON manifest: $jsonPath ($($files.Count) files)"

Write-Output "=== Done ===" -ForegroundColor Cyan
