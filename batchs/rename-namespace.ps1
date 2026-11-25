<#
    rename-namespace.ps1

    Given a staged copy of a folder, this:
      1. Replaces every occurrence of $OldNamespace with $NewNamespace inside
         the CONTENT of every text file (skipping known binary extensions).
      2. Renames any FILE whose name contains $OldNamespace.
      3. Renames any FOLDER whose name contains $OldNamespace (deepest paths
         first, so renaming a parent folder never breaks the path to a
         child we still need to process).

    Called once per staged source (bp, rp) from copy-parent-folder.bat.
#>

param(
    [Parameter(Mandatory = $true)][string]$StagePath,
    [Parameter(Mandatory = $true)][string]$OldNamespace,
    [Parameter(Mandatory = $true)][string]$NewNamespace
)

# Extensions we should NOT try to text-replace inside (binary/media/archives).
# Add to this list if your project uses other binary file types.
$SkipExtensions = @(
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tga', '.ico',
    '.ogg', '.wav', '.mp3', '.fsb',
    '.ttf', '.otf',
    '.zip', '.mcpack', '.mcaddon',
    '.exe', '.dll', '.bin', '.dat', '.nbt'
)

if ($OldNamespace -eq $NewNamespace) {
    Write-Host "  Namespace unchanged ('$OldNamespace'); skipping rename/replace for $StagePath"
    exit 0
}

if (-not (Test-Path -LiteralPath $StagePath)) {
    Write-Host "  Stage path not found, skipping: $StagePath"
    exit 0
}

Write-Host "  Processing: $StagePath"
$escapedOld = [regex]::Escape($OldNamespace)

# Read and write as UTF-8 WITHOUT a byte-order mark. Windows PowerShell 5.1's
# `Set-Content -Encoding UTF8` always prepends a BOM, and `Get-Content` with
# no -Encoding reads BOM-less UTF-8 as ANSI. Together they (a) made every
# rewritten .json fail to parse in obfuscate-json.js, (b) can put a BOM in
# front of .mcfunction / .lang files, and (c) garble non-ASCII text such as
# the translated .lang files. ReadAllText still strips a BOM if one exists.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# --- 1. Replace text content inside files (do this BEFORE any renaming,
#         while paths are still the original ones) ---
Get-ChildItem -LiteralPath $StagePath -Recurse -File | ForEach-Object {
    if ($SkipExtensions -contains $_.Extension.ToLower()) { return }

    try {
        $content = [System.IO.File]::ReadAllText($_.FullName, $utf8NoBom)
    } catch {
        return
    }
    if ($null -eq $content) { return }
    if ($content -notmatch $escapedOld) { return }

    $updated = $content -replace $escapedOld, $NewNamespace
    [System.IO.File]::WriteAllText($_.FullName, $updated, $utf8NoBom)
    Write-Host "    content updated: $($_.FullName.Substring($StagePath.Length))"
}

# --- 2. Rename files whose name contains the namespace ---
Get-ChildItem -LiteralPath $StagePath -Recurse -File |
    Sort-Object { $_.FullName.Length } -Descending |
    ForEach-Object {
        if ($_.BaseName -like "*$OldNamespace*") {
            $newName = ($_.BaseName -replace $escapedOld, $NewNamespace) + $_.Extension
            Rename-Item -LiteralPath $_.FullName -NewName $newName -Force
            Write-Host "    file renamed: $($_.Name) -> $newName"
        }
    }

# --- 3. Rename folders whose name contains the namespace (deepest first) ---
Get-ChildItem -LiteralPath $StagePath -Recurse -Directory |
    Sort-Object { $_.FullName.Length } -Descending |
    ForEach-Object {
        if ($_.Name -like "*$OldNamespace*") {
            $newName = $_.Name -replace $escapedOld, $NewNamespace
            Rename-Item -LiteralPath $_.FullName -NewName $newName -Force
            Write-Host "    folder renamed: $($_.Name) -> $newName"
        }
    }

Write-Host "  Namespace rename/replace complete for: $StagePath"
exit 0
