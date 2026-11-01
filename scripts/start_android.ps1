param(
  [string]$AvdName = "Medium_Phone_API_36.1",
  [string]$DeviceId = "emulator-5554",
  [string]$ApiBaseUrl = "https://sandbar-badass-subfloor.ngrok-free.dev/api",
  [switch]$NoDds
)

$sdk = if ($env:ANDROID_SDK_ROOT) {
  $env:ANDROID_SDK_ROOT
} elseif ($env:ANDROID_HOME) {
  $env:ANDROID_HOME
} else {
  "$env:LOCALAPPDATA\Android\sdk"
}

$adb = Join-Path $sdk "platform-tools\adb.exe"
$emulator = Join-Path $sdk "emulator\emulator.exe"

if (-not (Test-Path $adb) -or -not (Test-Path $emulator)) {
  throw "找不到 Android SDK。請確認 Android Studio 與 Android SDK 已安裝。"
}

& $adb start-server | Out-Null
$deviceLine = (& $adb devices | Select-String ("^{0}\s+" -f [regex]::Escape($DeviceId)))
$deviceStatus = if ($deviceLine) {
  ($deviceLine -split "\s+")[1]
} else {
  ""
}

if ($deviceStatus -eq "offline") {
  Write-Host "Android 裝置目前 offline，重新啟動 ADB..."
  & $adb kill-server | Out-Null
  & $adb start-server | Out-Null
  Start-Sleep -Seconds 2
  $deviceLine = (& $adb devices | Select-String ("^{0}\s+" -f [regex]::Escape($DeviceId)))
  $deviceStatus = if ($deviceLine) {
    ($deviceLine -split "\s+")[1]
  } else {
    ""
  }
}

if ($deviceStatus -ne "device") {
  Write-Host "啟動 Android 模擬器 $AvdName..."
  Start-Process -FilePath $emulator -ArgumentList "-avd", $AvdName, "-no-snapshot", "-no-boot-anim", "-gpu", "swiftshader_indirect", "-netdelay", "none", "-netspeed", "full"
}

$deadline = (Get-Date).AddSeconds(120)
$ready = $false
while ((Get-Date) -lt $deadline) {
  $deviceReady = (& $adb devices) -match "$DeviceId\s+device"
  if ($deviceReady) {
    $bootCompleted = (& $adb -s $DeviceId shell getprop sys.boot_completed 2>$null).Trim()
    if ($bootCompleted -eq "1") {
      $ready = $true
      break
    }
  }
  Start-Sleep -Seconds 2
}

if (-not $ready) {
  throw "Android 模擬器 $DeviceId 未在 120 秒內完成開機，請確認模擬器視窗不是 offline。"
}

Write-Host "啟動 Flutter Android 應用程式..."
$flutterArgs = @(
  "run",
  "-d", $DeviceId,
  "--device-timeout", "120",
  "--dart-define=API_BASE_URL=$ApiBaseUrl"
)
if ($NoDds) {
  $flutterArgs += "--no-dds"
  Write-Host "已停用 Dart Development Service（僅建議用於服務協定連線失敗時）。"
}
flutter @flutterArgs