# SCRIPT START

#region Prerequisite: Ensure ExchangeOnlineManagement Module is Present and Loaded
$moduleName = "ExchangeOnlineManagement"

Write-Host "Checking for the '$moduleName' module..."

if (-not (Get-Module -Name $moduleName -ListAvailable)) {
    Write-Host "'$moduleName' module not found. Attempting to install it..."
    try {
        # Try installing for the current user first, as it generally requires fewer permissions.
        # If that fails, it will fall back to attempting a global install.
        Install-Module -Name $moduleName -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
        Write-Host "'$moduleName' module installed successfully for the current user."
    }
    catch {
        Write-Warning "Failed to install '$moduleName' module for the current user. Attempting a global installation (may require elevated permissions)."
        try {
            Install-Module -Name $moduleName -Force -Confirm:$false -ErrorAction Stop
            Write-Host "'$moduleName' module installed successfully globally."
        }
        catch {
            Write-Error "Failed to install '$moduleName' module globally. Please run PowerShell as Administrator and ensure your PowerShell Gallery is configured correctly."
            Write-Error "Error Details: $($_.Exception.Message)"
            exit 1
        }
    }
}
else {
    Write-Host "'$moduleName' module is already installed."
}

# Import the module. Ensure it's loaded into the current session.
Write-Host "Importing the '$moduleName' module..."
try {
    Import-Module -Name $moduleName -ErrorAction Stop
    Write-Host "'$moduleName' module imported successfully."
}
catch {
    Write-Error "Failed to import the '$moduleName' module. Error Details: $($_.Exception.Message)"
    exit 1
}
#endregion

#region 1. Connect to Exchange Online
Write-Host "Attempting to connect to Exchange Online..."

try {
    # Connect-ExchangeOnline opens an authentication window.
    # -ShowBanner:$false suppresses the informational banner after connection.
    Connect-ExchangeOnline -ShowBanner:$false

    Write-Host "Successfully connected to Exchange Online."
}
catch {
    Write-Error "Failed to connect to Exchange Online. Please ensure you have an active internet connection and valid credentials."
    Write-Error "Error Details: $($_.Exception.Message)"
    # Exit the script if connection fails as subsequent commands will not work.
    exit 1
}
#endregion

#region 2. Define Output Path
# Get the current date and time for the filename
$date = Get-Date -Format "yyyyMMdd_HHmmss"
$scriptName = $MyInvocation.MyCommand.Name -replace '\.ps1$', '' # Gets script name without extension
$outputFileName = "ExchangeOnline_EmailAppStatus_$date.csv"
$outputPath = Join-Path -Path $PSScriptRoot -ChildPath $outputFileName

# Ensure the output directory exists
$outputDirectory = Split-Path -Path $outputPath -Parent
if (-not (Test-Path -Path $outputDirectory)) {
    Write-Host "Creating output directory: $outputDirectory"
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

Write-Host "Output file will be saved to: $outputPath"
#endregion

#region 3. Initialize Results Array
$results = @()
Write-Host "Starting to retrieve mailbox email app settings. This may take some time depending on the number of users..."
#endregion

#region 4. Get all User Mailboxes and their CAS Settings
try {
    # Get all user mailboxes. -ResultSize Unlimited ensures all are retrieved.
    # Filter for 'UserMailbox' to exclude shared, room, resource mailboxes etc.
    $mailboxes = Get-Mailbox -ResultSize Unlimited | Where-Object { $_.RecipientTypeDetails -eq "UserMailbox" }

    Write-Host "Found $($mailboxes.Count) user mailboxes to process."

    if ($mailboxes.Count -eq 0) {
        Write-Warning "No user mailboxes found. Exiting script."
        # Disconnect before exiting if no mailboxes found
        Disconnect-ExchangeOnline -Confirm:$false
        exit 0
    }

    $i = 0
    foreach ($mailbox in $mailboxes) {
        $i++
        Write-Progress -Activity "Processing Mailboxes" -Status "Processing $($mailbox.DisplayName) ($i of $($mailboxes.Count))" -PercentComplete (($i / $mailboxes.Count) * 100)

        try {
            # Get Client Access Service (CAS) settings for the current mailbox
            $casMailbox = Get-CASMailbox -Identity $mailbox.UserPrincipalName -ErrorAction Stop

            $results += [PSCustomObject]@{
                UserPrincipalName = $mailbox.UserPrincipalName
                DisplayName       = $mailbox.DisplayName
                OWAEnabled        = $casMailbox.OWAEnabled      # Outlook on the web
                MAPIEnabled       = $casMailbox.MAPIEnabled     # Outlook desktop client
                POP3Enabled       = $casMailbox.POP3Enabled     # POP3 protocol
                IMAP4Enabled      = $casMailbox.IMAP4Enabled    # IMAP4 protocol
                ActiveSyncEnabled = $casMailbox.ActiveSyncEnabled # Mobile devices (Exchange ActiveSync)
                EWSEnabled        = $casMailbox.EWSEnabled      # Exchange Web Services (for some apps)
                # You can add other CAS properties if needed, e.g., PopBlockOnSend, ImapBlockOnSend
            }
        }
        catch {
            Write-Warning "Failed to retrieve CAS mailbox settings for '$($mailbox.UserPrincipalName)'. Error: $($_.Exception.Message)"
            # Add an entry even if there's an error, indicating the issue
            $results += [PSCustomObject]@{
                UserPrincipalName = $mailbox.UserPrincipalName
                DisplayName       = $mailbox.DisplayName
                OWAEnabled        = "Error"
                MAPIEnabled       = "Error"
                POP3Enabled       = "Error"
                IMAP4Enabled      = "Error"
                ActiveSyncEnabled = "Error"
                EWSEnabled        = "Error"
            }
        }
    }
}
catch {
    Write-Error "An error occurred while retrieving mailboxes or their settings: $($_.Exception.Message)"
}
#endregion

#region 5. Export Results to CSV
if ($results.Count -gt 0) {
    Write-Host "Exporting $($results.Count) entries to CSV..."
    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Export completed successfully! Data saved to: $outputPath"
    }
    catch {
        Write-Error "Failed to export results to CSV file. Error: $($_.Exception.Message)"
    }
}
else {
    Write-Warning "No data was collected to export to CSV."
}
#endregion

#region 6. Disconnect from Exchange Online
Write-Host "Disconnecting from Exchange Online..."
try {
    # -Confirm:$false prevents a confirmation prompt for disconnection.
    Disconnect-ExchangeOnline -Confirm:$false
    Write-Host "Successfully disconnected from Exchange Online."
}
catch {
    Write-Warning "An error occurred while disconnecting from Exchange Online: $($_.Exception.Message)"
}
#endregion

# SCRIPT END