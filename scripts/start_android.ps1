param(
  [string]$AvdName = "Medium_Phone_API_36.1",
  [string]$DeviceId = "emulator-5554",
  [string]$ApiBaseUrl = "https://sandbar-badass-subfloor.ngrok-free.dev/api"
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
$connected = (& $adb devices) -match "$DeviceId\s+device"
if (-not $connected) {
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
flutter run -d $DeviceId --device-timeout 120 "--dart-define=API_BASE_URL=$ApiBaseUrl"