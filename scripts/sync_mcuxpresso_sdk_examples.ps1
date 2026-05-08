param(
    [Parameter(Mandatory = $true)]
    [string]$SdkDir,

    [Parameter(Mandatory = $true)]
    [string]$RepoDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-ExistingPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    } else {
        Remove-Item -LiteralPath $Path -Force
    }
}

function New-HardlinkMirror {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $sourceRoot = (Resolve-Path -LiteralPath $Source).Path
    Remove-ExistingPath -Path $Destination
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    Get-ChildItem -LiteralPath $sourceRoot -Directory -Recurse -Force | ForEach-Object {
        $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart('\')
        New-Item -ItemType Directory -Path (Join-Path $Destination $relative) -Force | Out-Null
    }

    Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | ForEach-Object {
        $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart('\')
        $linkPath = Join-Path $Destination $relative
        $linkParent = Split-Path -Parent $linkPath

        if (-not (Test-Path -LiteralPath $linkParent)) {
            New-Item -ItemType Directory -Path $linkParent -Force | Out-Null
        }

        if (Test-Path -LiteralPath $linkPath) {
            Remove-Item -LiteralPath $linkPath -Force
        }

        New-Item -ItemType HardLink -Path $linkPath -Target $_.FullName | Out-Null
    }
}

$sdkRoot = (Resolve-Path -LiteralPath $SdkDir).Path
$repoRoot = (Resolve-Path -LiteralPath $RepoDir).Path

$commonSource = Join-Path $repoRoot 'boards\src\demo_apps\avb_tsn'
$commonDestination = Join-Path $sdkRoot 'examples\demo_apps\avb_tsn'

Write-Host "Mirroring common avb_tsn example files..."
New-HardlinkMirror -Source $commonSource -Destination $commonDestination

Get-ChildItem -LiteralPath (Join-Path $repoRoot 'boards') -Directory | Where-Object {
    $_.Name -ne 'src' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'demo_apps\avb_tsn'))
} | ForEach-Object {
    $board = $_.Name
    $boardSource = Join-Path $_.FullName 'demo_apps\avb_tsn'
    $boardDestination = Join-Path $sdkRoot "examples\_boards\$board\demo_apps\avb_tsn"

    Write-Host "Mirroring board avb_tsn files: $board"
    New-HardlinkMirror -Source $boardSource -Destination $boardDestination
}
