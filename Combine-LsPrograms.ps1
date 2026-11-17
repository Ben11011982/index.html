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
          -SourceFolder "C:\Robots\A;C:\Robots\B" -FilePattern "r*_70x87_rh*.ls"
      (separate multiple folders with ;)
#>

param(
    # ======================= SETTINGS (edit these) =======================

    # Folder(s) that hold the .ls files. List one or more, separated by commas.
    [string[]]$SourceFolder = @(
        "M:\Engineering\Automation\Fanuc Robot Backup\04112023\r1r2\mnt_data\md_ls",
        "M:\Engineering\Automation\Fanuc Robot Backup\04112023\r3r4\mnt_data\md_ls"
    ),

    # Naming convention to match.  *  = any characters,  ?  = exactly one character
    #   "r?_*.ls"          -> every robot (r1..r9), every program   (default)
    #   "r?_70x87_*.ls"    -> only the 70x87 programs
    #   "r?_*_rh_tg.ls"    -> only the _rh_tg programs
    [string]$FilePattern = "r?_*.ls",

    # Name of the combined file (saved in the FIRST SourceFolder unless a full path is given)
    [string]$OutputName = "Platform Programming.txt",

    # Also search sub-folders?  $true / $false
    [bool]$IncludeSubfolders = $false

    # =====================================================================
)

$ErrorActionPreference = "Stop"

# Allow several folders on the command line separated by ;
$SourceFolder = @($SourceFolder | ForEach-Object { $_ -split ';' } |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })

foreach ($folder in $SourceFolder) {
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        Write-Host "Folder not found: $folder" -ForegroundColor Red
        Read-Host "Press Enter to close"
        exit 1
    }
}

# Resolve output path (relative names go into the source folder)
if ([System.IO.Path]::IsPathRooted($OutputName)) {
    $OutputPath = $OutputName
} else {
    $OutputPath = Join-Path $SourceFolder[0] $OutputName
}

# Find matching files in every folder
$files = foreach ($folder in $SourceFolder) {
    $searchArgs = @{ LiteralPath = $folder; Filter = $FilePattern; File = $true }
    if ($IncludeSubfolders) { $searchArgs.Recurse = $true }
    Get-ChildItem @searchArgs
}
$files = $files |
    Where-Object { $_.FullName -ne $OutputPath -and $_.Extension -ieq ".ls" } |
    Sort-Object @{ Expression = {
        # Natural sort so r2 comes before r10
        [regex]::Replace($_.Name.ToLower(), '\d+', { $args[0].Value.PadLeft(10, '0') })
    } }

if (-not $files) {
    Write-Host "No files matching '$FilePattern' found in: $($SourceFolder -join ', ')" -ForegroundColor Yellow
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
    foreach ($folder in $SourceFolder) { $header += "Source folder : $folder$newline" }
    $header += "File pattern  : $FilePattern$newline"
    $header += "Created       : $(Get-Date -Format 'yyyy-MM-dd HH:mm')$newline"
    $header += "Files ($($files.Count)):$newline"
    foreach ($f in $files) { $header += "   $($f.Name)   ($($f.DirectoryName))$newline" }
    $header += $newline
    $bytes = $enc.GetBytes($header)
    $out.Write($bytes, 0, $bytes.Length)

    foreach ($f in $files) {
        $sep = "$divider$newline" + "FILE: $($f.Name)$newline" + "FROM: $($f.DirectoryName)$newline" + "$divider$newline"
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
