# SCRIPT TO GRANT FULL CONTROL TO THE CURRENTLY LOGGED-ON USER
# This script runs silently, logs all output, and provides an exit code.

# Initialize script status to failure (1)
$scriptStatus = 1

# --- Log File Configuration ---
$logDirectory = "C:\Temp"
$logFileName = "Allow-Local-User-To-Delete-Desktop-Items_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logFilePath = Join-Path -Path $logDirectory -ChildPath $logFileName

# Ensure the log directory exists
if (-not (Test-Path -Path $logDirectory)) {
    try {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }
    catch {
        # If the directory can't be created, log to a default location and exit
        Write-Output "ERROR: Could not create log directory $logDirectory. Exiting."
        exit 1
    }
}

# Function to write log messages
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFilePath -Value "[$timestamp] $Message"
}

# --- Main Script Logic ---

try {
    Write-Log "Starting script..."
    
    # Get the name of the currently logged-on user
    $standardUser = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
    
    # Check if a user is logged in to the console
    if ([string]::IsNullOrEmpty($standardUser)) {
        Write-Log "ERROR: No user is currently logged in. Exiting."
        $scriptStatus = 1
    }
    else {
        Write-Log "Granting permissions to: $standardUser"
        
        # Define the paths to the user's desktop and the public desktop
        $userDesktopPath = "$env:USERPROFILE\Desktop"
        $publicDesktopPath = "$env:PUBLIC\Desktop"
        
        # Get a list of all items (files and folders) on the desktop
        $desktopItems = Get-ChildItem -Path $userDesktopPath, $publicDesktopPath -Recurse -Force -ErrorAction SilentlyContinue
        
        if ($null -eq $desktopItems) {
            Write-Log "No desktop items found to modify."
            $scriptStatus = 0
        }
        else {
            $permissionSuccess = $true
            # Loop through each item and change its permissions
            foreach ($item in $desktopItems) {
                try {
                    # Get the current Access Control List (ACL) for the item
                    $acl = Get-Acl -Path $item.FullName
                    
                    # Create a new permission rule for the specific user account
                    $permission = "$standardUser", "FullControl", "None", "None", "Allow"
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
                    
                    # Add the new rule to the ACL and save the changes back to the item
                    $acl.AddAccessRule($rule)
                    Set-Acl -Path $item.FullName -AclObject $acl
                    
                    Write-Log "Successfully updated permissions on: $($item.FullName)"
                }
                catch {
                    Write-Log "ERROR: Failed to update permissions on: $($item.FullName). Error: $_"
                    $permissionSuccess = $false
                }
            }
            if ($permissionSuccess) {
                $scriptStatus = 0
            }
            else {
                $scriptStatus = 1
            }
        }
    }
    Write-Log "Script completed with status: $scriptStatus"
}
catch {
    # Catch any unhandled errors
    Write-Log "FATAL ERROR: $_"
    $scriptStatus = 1
}

# Exit with the final status code
exit $scriptStatus