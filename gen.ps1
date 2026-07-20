$ErrorActionPreference = "Stop"
$serverDir = $PSScriptRoot
$outputFile = Join-Path $serverDir "manifest_seed.sql"
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine("TRUNCATE pwp_core.file_manifests;")

$files = Get-ChildItem -LiteralPath $serverDir -Recurse -File | Where-Object {
    $fn = $_.FullName
    $fn -notlike "*\generate_manifest.ps1" -and
    $fn -notlike "*\gen.ps1" -and
    $fn -notlike "*\manifest_seed.sql" -and
    $fn -notlike "*\.connector\*" -and
    $fn -notlike "*\.index\*"
}

$header = "INSERT INTO file_manifests (file_path,file_size,sha256,version,category,mod_name,mod_description,mod_optional) VALUES"
$batchSize = 500

for ($i = 0; $i -lt $files.Count; $i += $batchSize) {
    $batch = $files[$i..[Math]::Min($i + $batchSize - 1, $files.Count - 1)]
    [void]$sb.AppendLine($header)
    for ($j = 0; $j -lt $batch.Count; $j++) {
        $f = $batch[$j]
        $rel = $f.FullName.Substring($serverDir.Length + 1).Replace("\", "/")

        $cat = "game"
        if ($rel.StartsWith("mods/optional/")) { $cat = "mod" }
        elseif ($rel.StartsWith("mods/")) { $cat = "mod" }
        elseif ($rel.StartsWith("config/")) { $cat = "config" }
        elseif ($rel.StartsWith("libraries/")) { $cat = "library" }

        $mod = "NULL"
        $opt = "FALSE"
        if ($rel.StartsWith("mods/optional/")) {
            $opt = "TRUE"
            $mod = "'" + [System.IO.Path]::GetFileNameWithoutExtension($f.Name) + "'"
        } elseif ($rel -match "^mods/[^/]+\.jar$") {
            $mod = "'" + [System.IO.Path]::GetFileNameWithoutExtension($f.Name) + "'"
        }

        $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
        $epath = $rel -replace "'", "''"

        $comma = if ($j -eq $batch.Count - 1) { ";" } else { "," }
        [void]$sb.AppendLine("('$epath', $($f.Length), '$hash', 'latest', '$cat', $mod, NULL, $opt)$comma")
    }
}

$sb.ToString() | Out-File -LiteralPath $outputFile -Encoding UTF8
Write-Output "DONE: $($files.Count) files -> $outputFile"

# ── Generate manifest.json (for Launcher GitHub raw update) ──
$jsonFiles = @()
foreach ($f in $files) {
    $rel = $f.FullName.Substring($serverDir.Length + 1).Replace("\", "/")
    $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
    $jsonFiles += @{
        path = $rel
        size = $f.Length
        sha256 = $hash
    }
}
$jsonOutput = @{ files = $jsonFiles } | ConvertTo-Json -Compress
$jsonOutput | Out-File -LiteralPath (Join-Path $serverDir "manifest.json") -Encoding UTF8
Write-Output "DONE: $($files.Count) files -> manifest.json"
