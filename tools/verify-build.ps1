param(
    [string]$ManifestPath = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $Root "build.luau"
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "build manifest not found: $ManifestPath"
}

$Manifest = Get-Content -LiteralPath $ManifestPath -Raw
$RevisionMatch = [regex]::Match($Manifest, 'revision\s*=\s*"([0-9a-f]+)"')
$CountMatch = [regex]::Match($Manifest, 'fileCount\s*=\s*(\d+)')
if (-not $RevisionMatch.Success -or -not $CountMatch.Success) {
    throw "build.luau is missing revision or fileCount"
}

$Rows = New-Object System.Collections.Generic.List[object]
$Pattern = '\["([^"]+)"\]\s*=\s*"([0-9a-f]{64})"'
foreach ($Match in [regex]::Matches($Manifest, $Pattern)) {
    $Rows.Add([pscustomobject]@{
        Path = $Match.Groups[1].Value
        Hash = $Match.Groups[2].Value.ToLowerInvariant()
    })
}

$ExpectedCount = [int]$CountMatch.Groups[1].Value
if ($Rows.Count -ne $ExpectedCount) {
    throw "manifest fileCount=$ExpectedCount but parsed $($Rows.Count) file rows"
}

$FingerprintBuilder = New-Object System.Text.StringBuilder
foreach ($Row in ($Rows | Sort-Object Path)) {
    $FullPath = Join-Path $Root ($Row.Path.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $FullPath)) {
        throw "manifest references missing file: $($Row.Path)"
    }

    $Actual = (Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Actual -ne $Row.Hash) {
        throw "hash mismatch: $($Row.Path) expected=$($Row.Hash.Substring(0,12)) actual=$($Actual.Substring(0,12))"
    }
    [void]$FingerprintBuilder.Append($Row.Path).Append([char]0).Append($Actual).Append("`n")
}

$Sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($FingerprintBuilder.ToString())
    $ActualRevision = ([System.BitConverter]::ToString($Sha.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant()
} finally {
    $Sha.Dispose()
}

$ExpectedRevision = $RevisionMatch.Groups[1].Value.ToLowerInvariant()
if ($ActualRevision -ne $ExpectedRevision) {
    throw "revision mismatch expected=$ExpectedRevision actual=$ActualRevision"
}

Write-Host "[verify] build.luau valid: $($ActualRevision.Substring(0,12)) ($($Rows.Count) files)"
