# Ensure Windows Forms assembly is loaded
Add-Type -AssemblyName System.Windows.Forms

# Define the path to FFmpeg
$ffmpegPath = "C:\Users\LocalAdmin.HOME-BLACKBOX\OneDrive\Desktop\ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe"

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

# Show dialog and check if OK was clicked
if ($folderBrowserDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $selectedFolder = $folderBrowserDialog.SelectedPath
    Write-Host "Selected folder: $selectedFolder" -ForegroundColor Cyan
    
    # Get all MP4 files and sort by name
    $mp4Files = Get-ChildItem -Path $selectedFolder -Filter "*.mp4" -File | Sort-Object Name
    
    if ($mp4Files.Count -eq 0) {
        Write-Host "No MP4 files found in: $selectedFolder" -ForegroundColor Yellow
        pause
        exit
    }
    
    # List detected files for debugging
    Write-Host "Detected MP4 files ($($mp4Files.Count)):"
    $mp4Files | ForEach-Object { Write-Host " - $($_.Name)" }
    
    # Get first file name for output
    $firstFile = $mp4Files[0]
    Write-Host "First file selected: $($firstFile.Name)"
    $firstFileName = [System.IO.Path]::GetFileNameWithoutExtension($firstFile.Name)
    Write-Host "Extracted base name: $firstFileName"
    
    # Fallback if firstFileName is empty or invalid
    if ([string]::IsNullOrWhiteSpace($firstFileName)) {
        Write-Host "Warning: First file name is empty or invalid. Using 'merged' as fallback." -ForegroundColor Yellow
        $firstFileName = "merged"
    }
    Write-Host "Final base name for output: $firstFileName" -ForegroundColor Cyan
    
    # Create temporary folder for preprocessed files
    $tempFolder = Join-Path $selectedFolder "temp_merge"
    if (-not (Test-Path $tempFolder)) {
        New-Item -Path $tempFolder -ItemType Directory | Out-Null
        Write-Host "Created temporary folder: $tempFolder" -ForegroundColor Green
    }
    
    # Preprocess files to fix timestamps
    $preprocessedFiles = @()
    $index = 1
    foreach ($file in $mp4Files) {
        $tempOutput = Join-Path $tempFolder "temp_$index.mp4"
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
        }
        catch {
            Write-Host "Error preprocessing $($file.Name): $_" -ForegroundColor Red
            continue
        }
        $index++
    }
    
    if ($preprocessedFiles.Count -eq 0) {
        Write-Host "No files preprocessed successfully. Aborting merge." -ForegroundColor Red
        Remove-Item $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        pause
        exit
    }
    
    # Create temporary file list for ffmpeg
    $tempFileList = Join-Path $selectedFolder "filelist.txt"
    $fileListContent = $preprocessedFiles | ForEach-Object { 
        $escapedPath = $_.FullName -replace "'", "''"
        "file '$escapedPath'"
    }
    # Write file list without BOM
    [System.IO.File]::WriteAllLines($tempFileList, $fileListContent, [System.Text.UTF8Encoding]::new($false))
    
    # Show file list content
    Write-Host "File list content (preprocessed files):"
    Get-Content $tempFileList | ForEach-Object { Write-Host " - $_" }
    
    # Set output file path
    $outputFileName = "$firstFileName_merged.mp4"
    $outputFile = Join-Path $selectedFolder $outputFileName
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
    }
    catch {
        Write-Host "Error during merge: $_" -ForegroundColor Red
    }
    
    # Clean up temporary files and folder
    Remove-Item $tempFileList -ErrorAction SilentlyContinue
    Remove-Item $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
}
else {
    Write-Host "No folder selected." -ForegroundColor Yellow
}

pause