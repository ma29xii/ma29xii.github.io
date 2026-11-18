[CmdletBinding()]
param(
    [Parameter()]
    [string]$Ipa = (Join-Path $env:USERPROFILE 'Downloads\Health.ipa'),

    [Parameter(Mandatory)]
    [string]$EnvDatei
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$inputIpa = Get-Item -LiteralPath $Ipa
if ($inputIpa.PSIsContainer -or $inputIpa.Extension -ine '.ipa') {
    throw 'Bitte eine IPA-Datei angeben.'
}
if ($inputIpa.Name -ilike '*-mit-Coach.ipa') {
    throw 'Bitte das urspruengliche IPA als Eingabe angeben.'
}

$coachKeys = [ordered]@{}
$accounts = @{ ANTHROPIC_API_KEY = 'anthropic'; OPENAI_API_KEY = 'openai' }
foreach ($line in (Get-Content -LiteralPath $EnvDatei -Encoding UTF8)) {
    if ($line -cnotmatch '^\s*(?:export\s+)?(ANTHROPIC_API_KEY|OPENAI_API_KEY)\s*=\s*(.*)$') {
        continue
    }
    $account = $accounts[$Matches[1]]
    $value = $Matches[2].Trim()
    if (!$value -or $value.StartsWith('#')) {
        $coachKeys.Remove($account)
        continue
    }
    if ($value -cmatch '^(?:"([A-Za-z0-9._~-]{0,2048})"|''([A-Za-z0-9._~-]{0,2048})''|([A-Za-z0-9._~-]{1,2048}))(?:\s+#.*)?$') {
        $value = $Matches[1]
        if ($null -eq $value) { $value = $Matches[2] }
        if ($null -eq $value) { $value = $Matches[3] }
        if ($value) { $coachKeys[$account] = $value }
        else { $coachKeys.Remove($account) }
    }
    else {
        throw 'Ein Coach-Schluessel hat ein ungueltiges Format.'
    }
}

$hasAnthropic = if ($coachKeys.Contains('anthropic')) { 'ja' } else { 'nein' }
$hasOpenAI = if ($coachKeys.Contains('openai')) { 'ja' } else { 'nein' }
if ($coachKeys.Count -eq 0) {
    Write-Output "Anthropic: $hasAnthropic"
    Write-Output "OpenAI: $hasOpenAI"
    throw 'Kein Coach-Schluessel vorhanden.'
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$output = Join-Path $inputIpa.DirectoryName 'Health-mit-Coach.ipa'
$temporary = Join-Path $inputIpa.DirectoryName ("Health-" + [guid]::NewGuid().ToString('N') + "-mit-Coach.ipa")
try {
    [IO.File]::Copy($inputIpa.FullName, $temporary)
    $zip = [IO.Compression.ZipFile]::Open($temporary, [IO.Compression.ZipArchiveMode]::Update)
    try {
        if ($null -eq $zip.GetEntry('Payload/Forma.app/Info.plist')) {
            throw 'Die IPA enthaelt keine Forma-App.'
        }
        $entryPath = 'Payload/Forma.app/coach-keys.json'
        foreach ($existing in @($zip.Entries | Where-Object { $_.FullName -ieq $entryPath })) {
            $existing.Delete()
        }
        $json = ConvertTo-Json -InputObject $coachKeys -Compress
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        $entry = $zip.CreateEntry($entryPath)
        $stream = $entry.Open()
        try {
            $stream.Write($bytes, 0, $bytes.Length)
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $zip.Dispose()
    }

    if ([IO.File]::Exists($output)) {
        [IO.File]::Replace($temporary, $output, [NullString]::Value)
    }
    else {
        [IO.File]::Move($temporary, $output)
    }
}
finally {
    if ([IO.File]::Exists($temporary)) {
        Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue
    }
}

Write-Output "Anthropic: $hasAnthropic"
Write-Output "OpenAI: $hasOpenAI"
