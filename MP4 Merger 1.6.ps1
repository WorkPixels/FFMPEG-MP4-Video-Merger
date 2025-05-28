# Initialize all variables to $null
$ffmpegPath = $null
$folderBrowserDialog = $null
$form = $null
$selectedFolder = $null
$folderContents = $null
$videoFiles = $null
$firstFile = $null
$firstFileName = $null
$tempFolder = $null
$preprocessedFiles = $null
$tempFileList = $null
$fileListContent = $null
$outputFileName = $null
$outputFile = $null
$ffmpegCommand = $null
$index = $null
$tempOutput = $null
$preprocessCommand = $null

# Ensure Windows Forms assembly is loaded
Add-Type -AssemblyName System.Windows.Forms

# Define the path to FFmpeg
$ffmpegPath = "C:\Users\LocalAdmin.HOME-BLACKBOX\OneDrive\Desktop\ffmpeg-master-latest-win64-gpl-shared\bin\ffmpeg.exe"

# Check if FFmpeg exists
if (-not (Test-Path $ffmpegPath)) {
    Write-Host "FFmpeg not found at: $ffmpegPath" -ForegroundColor Red
    pause
    exit
}

# Create folder browser dialog
$folderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowserDialog.Description = "Select folder containing MP4 files to merge"
$folderBrowserDialog.ShowNewFolderButton = $false

# Create a form to make the dialog topmost
$form = New-Object System.Windows.Forms.Form
$form.TopMost = $true
$form.Visible = $false

# Show dialog and check if OK was clicked
if ($folderBrowserDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
    $selectedFolder = $folderBrowserDialog.SelectedPath
    Write-Host "Selected folder (raw): $selectedFolder" -ForegroundColor Cyan
    
    # Normalize the folder path to handle special characters
    try {
        $selectedFolder = [System.IO.Path]::GetFullPath($selectedFolder)
        Write-Host "Normalized folder path: $selectedFolder" -ForegroundColor Cyan
    } catch {
        Write-Host "Error normalizing folder path: $_" -ForegroundColor Red
        pause
        exit
    }
    
    # List all files in folder for debugging
    Write-Host "Attempting to list folder contents..." -ForegroundColor Cyan
    try {
        $folderContents = Get-ChildItem -LiteralPath $selectedFolder -ErrorAction Stop
        if ($folderContents.Count -eq 0) {
            Write-Host "Folder is empty or no files could be enumerated." -ForegroundColor Yellow
        } else {
            Write-Host "Folder contents:"
            $folderContents | ForEach-Object { Write-Host " - $($_.Name) ($($_.Extension))" }
        }
    } catch {
        Write-Host "Error listing folder contents: $_" -ForegroundColor Red
        Write-Host "Attempting to continue despite folder access issue..." -ForegroundColor Yellow
    }
    
    # Get all video files (mp4, m4v, mov) and sort by name
    try {
        $videoFiles = Get-ChildItem -LiteralPath $selectedFolder -File -Force -ErrorAction Stop | 
            Where-Object { $_.Extension -match '^\.(mp4|m4v|mov)$' -and $_.Length -gt 0 -and $_.Name -notlike '*uTorrentPartFile*' } | 
            Sort-Object Name
    } catch {
        Write-Host "Error detecting video files: $_" -ForegroundColor Red
        pause
        exit
    }
    
    if ($videoFiles.Count -eq 0) {
        Write-Host "No valid video files (mp4, m4v, mov) found in: $selectedFolder" -ForegroundColor Yellow
        Write-Host "All files in folder (retry):"
        try {
            Get-ChildItem -LiteralPath $selectedFolder | ForEach-Object { Write-Host " - $($_.Name) ($($_.Extension))" }
        } catch {
            Write-Host "Error retrying folder contents: $_" -ForegroundColor Red
        }
        pause
        exit
    }
    
    # List detected files for debugging
    Write-Host "Detected video files ($($videoFiles.Count)):"
    $videoFiles | ForEach-Object { Write-Host " - $($_.Name) ($($_.Extension)) [Size: $($_.Length) bytes]" }
    
    # Get first file name for output
    $firstFile = $videoFiles[0]
    Write-Host "First file selected: $($firstFile.Name) ($($firstFile.Extension))" -ForegroundColor Green
    
    # Extract and sanitize base name
    $firstFileName = [System.IO.Path]::GetFileNameWithoutExtension($firstFile.Name)
    Write-Host "Raw base name: $firstFileName" -ForegroundColor Green
    
    # Sanitize the base name (remove invalid characters and replace spaces with underscores)
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''
    $firstFileName = $firstFileName -replace "[$invalidChars]", ''
    $firstFileName = $firstFileName -replace '\s+', '_'
    
    # Fallback if base name is empty or invalid
    if ([string]::IsNullOrWhiteSpace($firstFileName)) {
        Write-Host "Warning: First file name is empty or invalid after sanitization. Using 'merged' as fallback." -ForegroundColor Yellow
        $firstFileName = "merged"
    }
    Write-Host "Sanitized base name: $firstFileName" -ForegroundColor Cyan
    
    # Set output file name with explicit check
    $outputFileName = "${firstFileName}_merged.mp4"
    Write-Host "Constructed output file name: $outputFileName" -ForegroundColor Cyan
    if ([string]::IsNullOrWhiteSpace($outputFileName) -or $outputFileName -eq '.mp4') {
        Write-Host "Warning: Output file name is invalid. Using 'merged.mp4' as fallback." -ForegroundColor Yellow
        $outputFileName = "merged.mp4"
    }
    Write-Host "Final output file name: $outputFileName" -ForegroundColor Cyan
    
    # Create temporary folder for preprocessed files
    $tempFolder = Join-Path -Path $selectedFolder "temp_merge"
    try {
        if (-not (Test-Path -LiteralPath $tempFolder)) {
            New-Item -Path $tempFolder -ItemType Directory -ErrorAction Stop | Out-Null
            Write-Host "Created temporary folder: $tempFolder" -ForegroundColor Green
        }
    } catch {
        Write-Host "Error creating temporary folder: $_" -ForegroundColor Red
        pause
        exit
    }
    
    # Preprocess files to fix timestamps
    $preprocessedFiles = @()
    $index = 1
    foreach ($file in $videoFiles) {
        $tempOutput = Join-Path -Path $tempFolder "temp_$index.mp4"
        Write-Host "Preprocessing $($file.Name) to fix timestamps..." -ForegroundColor Green
        $preprocessCommand = "& `"$ffmpegPath`" -i `"$($file.FullName)`" -c copy -fflags +genpts -start_at_zero `"$tempOutput`""
        try {
            Invoke-Expression $preprocessCommand
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Preprocessed: $tempOutput" -ForegroundColor Green
                $preprocessedFiles += [PSCustomObject]@{FullName = $tempOutput}
            } else {
                Write-Host "Failed to preprocess $($file.Name). Skipping." -ForegroundColor Red
                continue
            }
        } catch {
            Write-Host "Error preprocessing $($file.Name): $_" -ForegroundColor Red
            continue
        }
        $index++
    }
    
    if ($preprocessedFiles.Count -eq 0) {
        Write-Host "No files preprocessed successfully. Aborting merge." -ForegroundColor Red
        Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        pause
        exit
    }
    
    # Create temporary file list for ffmpeg
    $tempFileList = Join-Path -Path $selectedFolder "filelist.txt"
    $fileListContent = $preprocessedFiles | ForEach-Object { 
        $escapedPath = $_.FullName -replace "'", "''"
        "file '$escapedPath'"
    }
    # Write file list without BOM
    try {
        [System.IO.File]::WriteAllLines($tempFileList, $fileListContent, [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-Host "Error creating file list: $_" -ForegroundColor Red
        Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        pause
        exit
    }
    
    # Show file list content
    Write-Host "File list content (preprocessed files):"
    Get-Content -LiteralPath $tempFileList | ForEach-Object { Write-Host " - $_" }
    
    # Set output file path
    $outputFile = Join-Path -Path $selectedFolder $outputFileName
    Write-Host "Output file will be: $outputFile" -ForegroundColor Cyan
    
    # Build and run ffmpeg command
    $ffmpegCommand = "& `"$ffmpegPath`" -f concat -safe 0 -i `"$tempFileList`" -c copy `"$outputFile`""
    Write-Host "Merging files into $outputFileName..." -ForegroundColor Green
    
    try {
        Invoke-Expression $ffmpegCommand
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Merge completed successfully: $outputFile" -ForegroundColor Green
        } else {
            Write-Host "FFmpeg merge failed with exit code $LASTEXITCODE. Check output for errors." -ForegroundColor Red
            Write-Host "Timestamp issues may require re-encoding." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Error during merge: $_" -ForegroundColor Red
    }
    
    # Clean up temporary files and folder
    Remove-Item -LiteralPath $tempFileList -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "No folder selected." -ForegroundColor Yellow
}

# Dispose of the form
$form.Dispose()

pause