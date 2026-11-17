# 1. Read the exact Android SDK path from android/local.properties
$adbPath = $null
$localProps = Join-Path $PSScriptRoot "android\local.properties"

if (Test-Path $localProps) {
    $sdkLine = Get-Content $localProps | Where-Object { $_ -match "^sdk\.dir=" } | Select-Object -First 1
    if ($sdkLine) {
        $sdkDir = ($sdkLine -replace "^sdk\.dir=", "").Replace("\\", "\").Replace("\:", ":")
        $candidateAdb = Join-Path $sdkDir "platform-tools\adb.exe"
        if (Test-Path $candidateAdb) {
            $adbPath = $candidateAdb
        }
    }
}

# Fallback to system PATH or default AppData location
if (-not $adbPath) {
    $cmd = Get-Command "adb" -ErrorAction SilentlyContinue
    if ($cmd) {
        $adbPath = $cmd.Source
    } elseif (Test-Path "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe") {
        $adbPath = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
    }
}

# 2. Set up Method 2 (USB Port Forwarding Fallback)
if ($adbPath) {
    Write-Host "Found adb at: $adbPath" -ForegroundColor DarkGray
    Write-Host "Configuring USB fallback tunnel (adb reverse tcp:8000 tcp:8000)..." -ForegroundColor Cyan
    & $adbPath reverse tcp:8000 tcp:8000
} else {
    Write-Host "WARNING: Could not locate adb.exe. Running on Wi-Fi URL only." -ForegroundColor DarkYellow
}

# Google sign-in (Clerk) uses the project's Clerk app by default (key in
# lib/services/clerk_google_sign_in.dart). Set $env:CLERK_PUBLISHABLE_KEY only
# to point the app at a different Clerk app.
$clerkArgs = @()
if ($env:CLERK_PUBLISHABLE_KEY) {
    $clerkArgs = @("--dart-define=CLERK_PUBLISHABLE_KEY=$($env:CLERK_PUBLISHABLE_KEY)")
    Write-Host "Google sign-in   : Clerk app from CLERK_PUBLISHABLE_KEY" -ForegroundColor Green
} else {
    Write-Host "Google sign-in   : project's Clerk app (default)" -ForegroundColor Green
}

# 3. Set up Method 1 (Auto-detect Laptop Wi-Fi IPv4 Address)
$ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq "Up" }).IPv4Address.IPAddress | Select-Object -First 1

if ($ip) {
    $wifiUrl = "http://${ip}:8000"
    Write-Host "Primary Wi-Fi URL : $wifiUrl" -ForegroundColor Green
    Write-Host "Fallback USB URL  : http://127.0.0.1:8000" -ForegroundColor Yellow
    flutter run --dart-define=WIFI_BACKEND_URL=$wifiUrl @clerkArgs
} else {
    Write-Host "No active Wi-Fi IP detected. Running on USB tunnel (http://127.0.0.1:8000)..." -ForegroundColor Yellow
    flutter run @clerkArgs
}