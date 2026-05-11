param(
    [Parameter(Mandatory = $true)]
    [string]$SdkDir,

    [Parameter(Mandatory = $true)]
    [string]$RepoDir,

    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    return $Path.Substring($Root.Length).TrimStart('\') -replace '\\', '/'
}

function Get-FileId {
    param([Parameter(Mandatory = $true)][string]$Path)

    $output = fsutil file queryfileid $Path 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query file ID: $Path"
    }

    foreach ($line in $output) {
        if ($line -match '0x[0-9a-fA-F]+') {
            return $Matches[0].ToLowerInvariant()
        }
    }

    throw "Could not parse file ID for: $Path"
}

function Test-HardlinkMirror {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $sourceRoot = (Resolve-Path -LiteralPath $Source).Path
    $destinationRoot = $Destination

    Write-Host "Checking $Label"

    if (-not (Test-Path -LiteralPath $destinationRoot)) {
        Write-Warning "Missing mirror directory: $destinationRoot"
        return 1
    }

    $destinationRoot = (Resolve-Path -LiteralPath $destinationRoot).Path
    $failures = 0
    $sourceFiles = @{}

    Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | ForEach-Object {
        $relative = Get-NormalizedRelativePath -Root $sourceRoot -Path $_.FullName
        $sourceFiles[$relative] = $_.FullName

        $destinationFile = Join-Path $destinationRoot ($relative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $destinationFile)) {
            Write-Warning "Missing mirror file: $relative"
            $failures++
            return
        }

        $sourceId = Get-FileId -Path $_.FullName
        $destinationId = Get-FileId -Path $destinationFile
        if ($sourceId -ne $destinationId) {
            Write-Warning "Broken hardlink: $relative"
            $failures++
        }
    }

    if ($Strict) {
        Get-ChildItem -LiteralPath $destinationRoot -File -Recurse -Force | ForEach-Object {
            $relative = Get-NormalizedRelativePath -Root $destinationRoot -Path $_.FullName
            if (-not $sourceFiles.ContainsKey($relative)) {
                Write-Warning "Extra mirror file: $relative"
                $failures++
            }
        }
    }

    return $failures
}

$sdkRoot = (Resolve-Path -LiteralPath $SdkDir).Path
$repoRoot = (Resolve-Path -LiteralPath $RepoDir).Path
$totalFailures = 0

$commonSource = Join-Path $repoRoot 'boards\src\demo_apps\avb_tsn'
$commonDestination = Join-Path $sdkRoot 'examples\demo_apps\avb_tsn'
$totalFailures += Test-HardlinkMirror -Source $commonSource -Destination $commonDestination -Label 'common avb_tsn example files'

Get-ChildItem -LiteralPath (Join-Path $repoRoot 'boards') -Directory | Where-Object {
    $_.Name -ne 'src' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'demo_apps\avb_tsn'))
} | ForEach-Object {
    $board = $_.Name
    $boardSource = Join-Path $_.FullName 'demo_apps\avb_tsn'
    $boardDestination = Join-Path $sdkRoot "examples\_boards\$board\demo_apps\avb_tsn"
    $totalFailures += Test-HardlinkMirror -Source $boardSource -Destination $boardDestination -Label "board avb_tsn files: $board"
}

if ($totalFailures -ne 0) {
    Write-Error "Hardlink verification failed with $totalFailures issue(s). Re-run sync_mcuxpresso_sdk_examples.ps1 to recreate the mirror."
    exit 1
}

Write-Host "Hardlink verification passed."
