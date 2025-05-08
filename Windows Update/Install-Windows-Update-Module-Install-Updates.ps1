   # Install the PSWindowsUpdate module (if not already installed)
   if (-not (Get-Module -ListAvailable PSWindowsUpdate -ErrorAction SilentlyContinue)) {
       Write-Warning "PSWindowsUpdate module not found.  Attempting to install..."
       try {
           Install-Module PSWindowsUpdate -Force
       } catch {
           Write-Error "Error installing PSWindowsUpdate module: $($_.Exception.Message)"
       }
   }

   # Check for updates
   Get-WindowsUpdate

   # Install all updates (accept all and ignore reboots)
   Install-WindowsUpdate -AcceptAll -IgnoreReboot

   # Optional: Check the update history
   #Get-WUHistory