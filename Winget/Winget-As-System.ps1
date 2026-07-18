$wingetPath = (Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Select-Object -Last 1).Path
& $wingetPath upgrade --all --accept-source-agreements --accept-package-agreements
