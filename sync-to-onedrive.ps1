# Sync new entries from the phone "suishouji" (CloudBase) into the OneDrive markdown.
# Run manually:  powershell -NoProfile -ExecutionPolicy Bypass -File .\sync-to-onedrive.ps1
param(
    [string]$MdFile = (Join-Path $env:USERPROFILE 'OneDrive\随手记.md')
)
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configJs  = Join-Path $scriptDir 'config.local.js'
$stateFile = Join-Path $scriptDir 'sync-state.json'

# Read endpoint + key from config.local.js (not tracked by git, never printed).
if (-not (Test-Path $configJs)) {
    throw "Missing config.local.js — copy config.example.js to config.local.js and fill in your values."
}
$js  = [System.IO.File]::ReadAllText($configJs)
$api = [regex]::Match($js, "API_URL\s*:\s*'([^']+)'").Groups[1].Value
$key = [regex]::Match($js, "KEY\s*:\s*'([^']+)'").Groups[1].Value
if (-not $api -or -not $key) {
    throw "config.local.js has no API_URL / KEY."
}

# Pull all entries oldest-first.
$rows = Invoke-RestMethod -Uri ($api + '/v1/rdb/rest/entries?select=*&order=created_at.asc&limit=10000') -Headers @{ Authorization = 'Bearer ' + $key }
$rows = @($rows)

# Load already-synced ids.
$syncedIds = @()
if (Test-Path $stateFile) {
    $st = [System.IO.File]::ReadAllText($stateFile) | ConvertFrom-Json
    if ($st -and $st.ids) { $syncedIds = @($st.ids) }
}

# First run: baseline only (do NOT import historical/test data into the markdown).
if (-not (Test-Path $stateFile)) {
    $ids = @($rows | ForEach-Object { $_.id })
    $json = @{ ids = $ids } | ConvertTo-Json
    [System.IO.File]::WriteAllText($stateFile, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Output ("Baseline established: " + $ids.Count + " historical record(s), not imported.")
    exit 0
}

$newRows = @($rows | Where-Object { $syncedIds -notcontains $_.id })
if ($newRows.Count -eq 0) {
    Write-Output 'No new records.'
    exit 0
}

$marker = '<!-- SYNC-APPEND-HERE -->'
$md = [System.IO.File]::ReadAllText($mdFile)

$lines = @()
foreach ($r in $newRows) {
    $ts = ''
    try { $ts = ([DateTimeOffset]::Parse($r.created_at)).ToString('yyyy-MM-dd HH:mm') }
    catch { $ts = [string]$r.created_at }
    if ($r.text) { $t = (($r.text) -replace "\s+", " ").Trim() } else { $t = '' }
    if ($r.image) { $tag = ' [img]' } else { $tag = '' }
    $lines += ("- " + $ts + "  " + $t + $tag)
}

$block = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
$md = $md.Replace($marker, $block + $marker)
[System.IO.File]::WriteAllText($mdFile, $md, [System.Text.UTF8Encoding]::new($false))

$syncedIds = @($syncedIds) + @($newRows | ForEach-Object { $_.id })
$json = @{ ids = $syncedIds } | ConvertTo-Json
[System.IO.File]::WriteAllText($stateFile, $json, [System.Text.UTF8Encoding]::new($false))

Write-Output ("Synced " + $newRows.Count + " new record(s).")
