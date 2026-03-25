# Download ONNX Runtime Windows prebuilt libraries
$ORT_VERSION = "1.24.3"
$OUT_DIR = "$PSScriptRoot\onnxruntime-win"

if (Test-Path "$OUT_DIR\lib\onnxruntime.lib") {
    Write-Host "ONNX Runtime Windows already at $OUT_DIR"
    exit 0
}

$URL = "https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-win-x64-${ORT_VERSION}.zip"
$TMP = "$env:TEMP\ort-win.zip"

Write-Host "Downloading ONNX Runtime $ORT_VERSION for Windows..."
Invoke-WebRequest -Uri $URL -OutFile $TMP

Write-Host "Extracting..."
New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null
Expand-Archive -Path $TMP -DestinationPath "$env:TEMP\ort-extract" -Force

# Move contents up one level
$extracted = Get-ChildItem "$env:TEMP\ort-extract" | Select-Object -First 1
Copy-Item -Path "$($extracted.FullName)\*" -Destination $OUT_DIR -Recurse -Force

Remove-Item $TMP -Force
Remove-Item "$env:TEMP\ort-extract" -Recurse -Force

Write-Host ""
Write-Host "ONNX Runtime Windows extracted to: $OUT_DIR"
Get-ChildItem $OUT_DIR
