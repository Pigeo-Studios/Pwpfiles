$ErrorActionPreference = "Stop"
$serverDir = $PSScriptRoot
$outputFile = Join-Path $serverDir "manifest_seed.sql"
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine("INSERT INTO file_manifests (file_path,file_size,sha256,version,category,mod_name,mod_description,mod_optional) VALUES")

$files = Get-ChildItem -LiteralPath $serverDir -Recurse -File | Where-Object {
    $fn = $_.FullName
    $fn -notlike "*\generate_manifest.ps1" -and
    $fn -notlike "*\gen.ps1" -and
    $fn -notlike "*\manifest_seed.sql" -and
    $fn -notlike "*\.connector\*" -and
    $fn -notlike "*\.index\*"
}

$count = 0
$total = $files.Count

foreach ($f in $files) {
    $count++
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
    if ($count -eq $total) { $comma = ";" } else { $comma = "," }

    [void]$sb.AppendLine("('$epath', $($f.Length), '$hash', 'latest', '$cat', $mod, NULL, $opt)$comma")
}

$sb.ToString() | Out-File -LiteralPath $outputFile -Encoding UTF8
Write-Output "DONE: $count files -> $outputFile"
