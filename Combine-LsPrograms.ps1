<#
    Combine-LsPrograms.ps1

    Pulls robot programs (.ls files) that match a naming convention from a folder
    and copies their contents, unchanged, into one combined text file.

    HOW TO USE
      1. Edit the three variables in the SETTINGS section below.
      2. Right-click this file -> "Run with PowerShell"
         (or double-click Combine-LsPrograms.bat).

    You can also override the settings from the command line without editing:
      powershell -ExecutionPolicy Bypass -File Combine-LsPrograms.ps1 `
          -SourceFolder "C:\Robots\Job123" -FilePattern "r*_70x87_rh*.ls"
#>

param(
    # ======================= SETTINGS (edit these) =======================

    # Folder that holds the .ls files
    [string]$SourceFolder = "C:\Robot Programs\Platform",

    # Naming convention to match.  *  = any characters,  ?  = exactly one character
    #   "r?_*.ls"          -> every robot (r1..r9), every program   (default)
    #   "r?_70x87_*.ls"    -> only the 70x87 programs
    #   "r?_*_rh_tg.ls"    -> only the _rh_tg programs
    [string]$FilePattern = "r?_*.ls",

    # Name of the combined file (saved in the SourceFolder unless a full path is given)
    [string]$OutputName = "Platform Programming.txt",

    # Also search sub-folders?  $true / $false
    [bool]$IncludeSubfolders = $false

    # =====================================================================
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
    Write-Host "Folder not found: $SourceFolder" -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

# Resolve output path (relative names go into the source folder)
if ([System.IO.Path]::IsPathRooted($OutputName)) {
    $OutputPath = $OutputName
} else {
    $OutputPath = Join-Path $SourceFolder $OutputName
}

# Find matching files
$searchArgs = @{ LiteralPath = $SourceFolder; Filter = $FilePattern; File = $true }
if ($IncludeSubfolders) { $searchArgs.Recurse = $true }

$files = Get-ChildItem @searchArgs |
    Where-Object { $_.FullName -ne $OutputPath -and $_.Extension -ieq ".ls" } |
    Sort-Object @{ Expression = {
        # Natural sort so r2 comes before r10
        [regex]::Replace($_.Name.ToLower(), '\d+', { $args[0].Value.PadLeft(10, '0') })
    } }

if (-not $files) {
    Write-Host "No files matching '$FilePattern' found in $SourceFolder" -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit 1
}

# Build the combined file.  File contents are copied byte-for-byte so the
# original formatting, spacing and line endings are kept exactly.
$enc     = [System.Text.Encoding]::ASCII
$newline = "`r`n"
$divider = ("=" * 80)

$out = [System.IO.File]::Create($OutputPath)
try {
    $header  = "PLATFORM PROGRAMMING$newline"
    $header += "Source folder : $SourceFolder$newline"
    $header += "File pattern  : $FilePattern$newline"
    $header += "Created       : $(Get-Date -Format 'yyyy-MM-dd HH:mm')$newline"
    $header += "Files ($($files.Count)):$newline"
    foreach ($f in $files) { $header += "   $($f.Name)$newline" }
    $header += $newline
    $bytes = $enc.GetBytes($header)
    $out.Write($bytes, 0, $bytes.Length)

    foreach ($f in $files) {
        $sep = "$divider$newline" + "FILE: $($f.Name)$newline" + "$divider$newline"
        $bytes = $enc.GetBytes($sep)
        $out.Write($bytes, 0, $bytes.Length)

        $content = [System.IO.File]::ReadAllBytes($f.FullName)
        $out.Write($content, 0, $content.Length)

        # Make sure the next divider starts on its own line
        if ($content.Length -gt 0 -and $content[$content.Length - 1] -ne 10) {
            $bytes = $enc.GetBytes($newline)
            $out.Write($bytes, 0, $bytes.Length)
        }
        $bytes = $enc.GetBytes($newline)
        $out.Write($bytes, 0, $bytes.Length)

        Write-Host "  added $($f.Name)"
    }
}
finally {
    $out.Close()
}

Write-Host ""
Write-Host "Combined $($files.Count) file(s) into:" -ForegroundColor Green
Write-Host "  $OutputPath"
Read-Host "Press Enter to close"
