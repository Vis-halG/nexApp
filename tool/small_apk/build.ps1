# Builds the arm64 APK that is shared for testing and keeps it under 10 MB:
# an obfuscated single-ABI release build, recompressed with zopfli, then
# aligned and signed again with the debug key the release build already uses.
#
#   powershell -ExecutionPolicy Bypass -File tool\small_apk\build.ps1 [-Output path]
param(
  [string]$Output = 'build\nexMusic-arm64.apk',
  [int]$Iterations = 15
)

$tool = $PSScriptRoot
Set-Location (Resolve-Path (Join-Path $tool '..\..') -ErrorAction Stop)

$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$buildTools = Get-ChildItem "$sdk\build-tools" -Directory -ErrorAction Stop |
  Sort-Object { [version]$_.Name } | Select-Object -Last 1
$zipalign = Join-Path $buildTools.FullName 'zipalign.exe'
$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'

flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build\symbols
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

if (-not (Test-Path "$tool\node_modules\@gfx\zopfli")) {
  npm install --prefix $tool --no-audit --no-fund
  if ($LASTEXITCODE -ne 0) { throw 'npm install failed' }
}

$work = 'build\small_apk'
New-Item -ItemType Directory -Force $work | Out-Null
node "$tool\repack-apk.cjs" 'build\app\outputs\flutter-apk\app-release.apk' "$work\unsigned.apk" $Iterations
if ($LASTEXITCODE -ne 0) { throw 'repack failed' }

& $zipalign -f 4 "$work\unsigned.apk" "$work\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }

& $apksigner sign --ks "$env:USERPROFILE\.android\debug.keystore" --ks-pass pass:android `
  --key-pass pass:android --ks-key-alias androiddebugkey --out $Output "$work\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw 'apksigner failed' }
& $apksigner verify $Output
if ($LASTEXITCODE -ne 0) { throw 'signature check failed' }

$bytes = (Get-Item $Output).Length
'{0}: {1:N0} bytes ({2:N2} MB)' -f $Output, $bytes, ($bytes / 1e6)
if ($bytes -ge 10000000) { Write-Warning 'The APK is 10 MB or larger.' }
