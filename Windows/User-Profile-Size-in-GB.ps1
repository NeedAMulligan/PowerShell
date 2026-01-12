# Get the computer name of the system
$ComputerName = $env:COMPUTERNAME

# Define the output CSV file path using the computer name
$OutputPath = "C:\temp\$($ComputerName)-user-profile-size.csv"

# --- Step to create C:\temp if it does not exist ---
# Check if the C:\temp directory exists. If not, create it.
# Out-Null is used to suppress any output from the New-Item command, ensuring silence.
If (-Not (Test-Path "C:\temp")) {
    New-Item -Path "C:\temp" -ItemType Directory | Out-Null
}
# ---------------------------------------------------

$Results = @()

# Get all user profiles on the computer
# We filter out any profiles that might not have a local path defined.
$UserProfiles = Get-WmiObject Win32_UserProfile | Where-Object { $_.LocalPath -ne $null }

foreach ($Profile in $UserProfiles) {
    $ProfilePath = $Profile.LocalPath

    # Only process if the profile directory actually exists on the disk.
    If (Test-Path $ProfilePath) {
        Try {
            # Get the total size of all files within the profile folder and its subfolders.
            # -Recurse ensures all subdirectories are included.
            # -ErrorAction SilentlyContinue prevents errors (e.g., permission issues) from stopping the script
            # or producing console output, maintaining the silent operation.
            $FolderSizeInBytes = (Get-ChildItem -LiteralPath $ProfilePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum

            # Convert the size from bytes to gigabytes and round to two decimal places.
            $FolderSizeInGB = [Math]::Round($FolderSizeInBytes / 1GB, 2)

            # Extract just the username (folder name) from the full profile path.
            $UserName = Split-Path -Path $ProfilePath -Leaf

            # Create a custom object to hold the profile's information.
            $ProfileObject = [PSCustomObject]@{
                UserName    = $UserName
                ProfilePath = $ProfilePath
                SizeGB      = $FolderSizeInGB
            }
            # Add the custom object to our results array.
            $Results += $ProfileObject
        }
        Catch {
            # In a silent script, we intentionally avoid any Write-Host or Write-Warning.
            # Any errors encountered (e.g., permissions) will not be displayed to the user.
            # If you needed to track these, you would add a logging mechanism here (e.g., writing to a log file).
        }
    } else {
        # If a profile path exists in WMI but the actual folder is missing, we skip it silently.
    }
}

# Export the collected profile data to the specified CSV file.
# -NoTypeInformation prevents PowerShell from adding a header line about the object type.
$Results | Export-Csv -Path $OutputPath -NoTypeInformation

# The script completes silently, without any final confirmation messages.
