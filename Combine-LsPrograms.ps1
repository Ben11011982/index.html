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

    # Programs to SKIP, even if they match FilePattern. List one or more, separated
    # by commas.  Leave as @() to skip nothing.
    #   @("*_tg.ls")                  -> skip all the _tg programs
    #   @("r?_83x87_*.ls")            -> skip all the 83x87 programs
    #   @("r1_70x87_rh.ls", "*_tg.ls") -> skip one exact file and all _tg programs
    [string[]]$ExcludePattern = @(),

    # Name of the combined file (saved in the FIRST SourceFolder unless a full path is given)
    [string]$OutputName = "Platform Programming.txt",

    # Also search sub-folders?  $true / $false
    [bool]$IncludeSubfolders = $false,

    # Label for each source folder, in the same order as SourceFolder.  The label
    # is shown on every program so same-name files (e.g. all_step.ls from r1r2 and
    # from r3r4) can be told apart.  Leave as @() to be asked each time it runs.
    #   @("R1R2", "R3R4")
    [string[]]$FolderLabels = @()

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

# Check the output path is valid before writing
try {
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
} catch {
    Write-Host "The output file path is not valid:" -ForegroundColor Red
    Write-Host "  $OutputPath"
    Write-Host "Check `$OutputName and `$SourceFolder in the SETTINGS section." -ForegroundColor Yellow
    Write-Host "(File names cannot contain  : * ? `" < > |  )"
    Read-Host "Press Enter to close"
    exit 1
}
Write-Host "Saving to: $OutputPath"

# Allow several exclude patterns on the command line separated by ;
$ExcludePattern = @($ExcludePattern | ForEach-Object { $_ -split ';' } |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })

# ---- Folder labels ---------------------------------------------------------
$FolderLabels = @($FolderLabels | ForEach-Object { $_ -split ';' } |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })

if ($SourceFolder.Count -eq 1) {
    $labels = @("")          # one folder: no label needed
} elseif ($FolderLabels.Count -eq $SourceFolder.Count) {
    $labels = $FolderLabels
} else {
    # Suggest the part of the path that is different between the folders
    # (e.g. "r1r2" and "r3r4")
    $parts = @($SourceFolder | ForEach-Object { ,($_.TrimEnd('\') -split '\\') })
    $diffIndex = -1
    $minLen = ($parts | ForEach-Object { $_.Count } | Measure-Object -Minimum).Minimum
    for ($i = 0; $i -lt $minLen; $i++) {
        $seg = @($parts | ForEach-Object { $_[$i].ToLower() } | Select-Object -Unique)
        if ($seg.Count -gt 1) { $diffIndex = $i; break }
    }

    Write-Host ""
    Write-Host "$($SourceFolder.Count) source folders found. Enter a label for each one."
    Write-Host "(Press Enter to use the suggestion in [brackets].)"
    $labels = @()
    for ($i = 0; $i -lt $SourceFolder.Count; $i++) {
        if ($diffIndex -ge 0) { $suggest = $parts[$i][$diffIndex].ToUpper() }
        else                  { $suggest = "FOLDER$($i + 1)" }
        Write-Host ""
        Write-Host "  $($SourceFolder[$i])"
        $answer = Read-Host "  Label [$suggest]"
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $suggest }
        $labels += $answer.Trim()
    }
    Write-Host ""
}

# ---- Find matching files in every folder ------------------------------------
# Names are checked with an exact wildcard match on the full file name only.
# (Get-ChildItem -Filter is NOT used, because Windows also matches the old
#  8.3 short names, so a pattern like "gen_*.ls" could pick up "genysis_1.ls".)
$files = for ($i = 0; $i -lt $SourceFolder.Count; $i++) {
    $searchArgs = @{ LiteralPath = $SourceFolder[$i]; File = $true }
    if ($IncludeSubfolders) { $searchArgs.Recurse = $true }
    foreach ($f in Get-ChildItem @searchArgs) {
        [pscustomobject]@{ File = $f; Label = $labels[$i]; Order = $i }
    }
}
$files = @($files |
    Where-Object { $_.File.FullName -ne $OutputPath -and $_.File.Extension -ieq ".ls" } |
    Where-Object { $_.File.Name -like $FilePattern } |
    Where-Object {
        $name = $_.File.Name
        -not ($ExcludePattern | Where-Object { $name -like $_ })
    } |
    Sort-Object @{ Expression = {
        # Natural sort so r2 comes before r10
        [regex]::Replace($_.File.Name.ToLower(), '\d+', { $args[0].Value.PadLeft(10, '0') })
    } }, Order)

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
    if ($ExcludePattern) { $header += "Excluded      : $($ExcludePattern -join ', ')$newline" }
    $header += "Created       : $(Get-Date -Format 'yyyy-MM-dd HH:mm')$newline"
    $header += "Files ($($files.Count)):$newline"
    if ($SourceFolder.Count -gt 1) {
        $header += "Folder labels :$newline"
        for ($i = 0; $i -lt $SourceFolder.Count; $i++) {
            $header += "   [$($labels[$i])]  $($SourceFolder[$i])$newline"
        }
    }
    foreach ($item in $files) {
        $tag = if ($item.Label) { "[$($item.Label)] " } else { "" }
        $header += "   $tag$($item.File.Name)$newline"
    }
    $header += $newline
    $bytes = $enc.GetBytes($header)
    $out.Write($bytes, 0, $bytes.Length)

    foreach ($item in $files) {
        $f   = $item.File
        $tag = if ($item.Label) { "[$($item.Label)] " } else { "" }
        $sep = "$divider$newline" + "FILE: $tag$($f.Name)$newline" + "FROM: $($f.DirectoryName)$newline" + "$divider$newline"
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

        Write-Host "  added $tag$($f.Name)"
    }
}
finally {
    $out.Close()
}

Write-Host ""
Write-Host "Combined $($files.Count) file(s) into:" -ForegroundColor Green
Write-Host "  $OutputPath"
Read-Host "Press Enter to close"
