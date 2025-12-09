# Custom Exit Codes
# 0 = Success (Deletion initiated)
# 1001 = Prerequisite Missing (Module not installed)
# 1002 = Connection Failed (M365/Security & Compliance) - **FIXED: Removed incompatible parameter.**
# 1003 = Search Failed to Create/Start
# 1004 = Purge Action Failed to Create/Start
# 1005 = Loop Limit Exceeded (Likely due to Purge limits)

# --- USER CONFIGURATION ---
# The target contact details
$ContactEmail = "staci.gelfound@aim-services.net"
$ContactName = "Staci Gelfound"
$SearchName = "PurgeContact_StaciGelfound_$(Get-Date -Format 'yyyyMMddHHmmss')"
# --- END USER CONFIGURATION ---

# Define the log file path and name
$LogFilePath = "C:\temp"
$LogFileName = "$($MyInvocation.MyCommand.Name.Replace('.ps1', ''))_$(Get-Date -Format 'yyyyMMddHHmmss').log"
$FullLogPath = Join-Path -Path $LogFilePath -ChildPath $LogFileName

# Function to write to log file
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][string]$Type = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Type] $Message"
    # Ensure C:\temp exists and write content silently
    if (-not (Test-Path $LogFilePath)) {
        New-Item -Path $LogFilePath -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    }
    Add-Content -Path $FullLogPath -Value $LogEntry -ErrorAction SilentlyContinue
}

# 1. Initialize Logging and Prerequisite Check
try {
    Write-Log -Message "--- Script Execution Started ---"
    Write-Log -Message "Target: $ContactName ($ContactEmail). Log File: $FullLogPath"

    # Check for ExchangeOnlineManagement module
    if (-not (Get-Module -Name ExchangeOnlineManagement -ListAvailable)) {
        Write-Log -Message "ERROR: ExchangeOnlineManagement module not found. Exiting." -Type "ERROR"
        exit 1001
    }
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Write-Log -Message "ExchangeOnlineManagement module loaded."
}
catch {
    # If logging setup fails, just exit
    exit 1000
}

# 2. Connect to Security & Compliance Center (SCC)
try {
    Write-Log -Message "Connecting to Security & Compliance Center..."
    # FIX APPLIED: Removed the incompatible '-SkipHeaderValidation' parameter.
    # NOTE: This still requires a highly privileged, non-interactive connection setup (e.g., Service Principal).
    $Session = Connect-IPPSSession -ErrorAction Stop 
    Write-Log -Message "Successfully established SCC session."
}
catch {
    Write-Log -Message "ERROR: Failed to connect to SCC. Details: $($_.Exception.Message)" -Type "ERROR"
    exit 1002
}

# 3. KQL Definition and Compliance Search Loop
$KQLQuery = "(ItemClass:IPM.Contact*) AND (EmailAddress:`"$ContactEmail`" OR Subject:`"$ContactName`")"
Write-Log -Message "KQL Query: $KQLQuery"
$PurgeLoopCount = 0
$MaxPurgeLoops = 3 # Due to deletion limits (often 10-100 items per mailbox per action execution)

try {
    do {
        $PurgeLoopCount++
        Write-Log -Message "Starting Purge Loop $PurgeLoopCount..."

        # A. Create and Start Search
        Write-Log -Message "Creating Compliance Search '$SearchName'..."
        # AllowNotFoundExchangeLocationsEnabled handles scenarios where some mailboxes might not exist or be provisioned yet.
        $Search = New-ComplianceSearch -Name $SearchName -ExchangeLocation All -ContentMatchQuery $KQLQuery -AllowNotFoundExchangeLocationsEnabled $true -ErrorAction Stop
        Start-ComplianceSearch -Identity $SearchName
        
        # B. Wait for Search Completion
        $i = 0
        do {
            Start-Sleep -Seconds 30
            $SearchStatus = Get-ComplianceSearch -Identity $SearchName -ErrorAction SilentlyContinue
            if ($i++ -gt 15) { # 7.5 minutes max wait
                Write-Log -Message "WARNING: Search timed out or failed to complete after 7.5 mins. Proceeding." -Type "WARNING"
                break
            }
        } while ($SearchStatus.Status -ne "Completed" -and $SearchStatus.Status -ne "Failed")
        
        if ($SearchStatus.Status -eq "Failed") {
            Write-Log -Message "ERROR: Compliance Search failed. Status: $($SearchStatus.StatusDetails)" -Type "ERROR"
            exit 1003
        }

        # C. Check Items Found
        $ItemsFound = 0
        try {
            # Use the Get-ComplianceSearch cmdlet to get the results/count
            $SearchStats = Get-ComplianceSearch -Identity $SearchName
            if ($SearchStats.Items -is [System.Collections.ICollection]) {
                $ItemsFound = $SearchStats.Items.Count
            } elseif ($SearchStats.Items -ne $null) {
                # Handle single item scenario
                $ItemsFound = 1
            }
        } catch {
             Write-Log -Message "WARNING: Could not reliably determine ItemsFound count. Proceeding cautiously." -Type "WARNING"
             # Assume at least one item was found to run the purge
             $ItemsFound = 1 
        }

        Write-Log -Message "Search completed. Found $ItemsFound items matching criteria."

        if ($ItemsFound -eq 0) {
            Write-Log -Message "SUCCESS: No more items found. Contact removal is complete." -Type "SUCCESS"
            break # Exit the loop
        }

        # D. Execute Hard Delete Action
        Write-Log -Message "ATTENTION: Creating PURGE action to HARD DELETE potentially $ItemsFound contacts." -Type "WARNING"
        # -Confirm:$false ensures complete silence
        $PurgeAction = New-ComplianceSearchAction -SearchName $SearchName -Purge -PurgeType HardDelete -Confirm:$false -ErrorAction Stop
        Write-Log -Message "Purge Action '$($PurgeAction.Name)' initiated."
        
        # E. Clean up search and wait for next loop (if needed)
        Remove-ComplianceSearch -Identity $SearchName -Confirm:$false -ErrorAction SilentlyContinue
        
        if ($PurgeLoopCount -ge $MaxPurgeLoops) {
            Write-Log -Message "ERROR: Maximum purge loops ($MaxPurgeLoops) reached. Some items may remain due to throttling/limits." -Type "ERROR"
            exit 1005
        }

        Write-Log -Message "Waiting 60 seconds before next loop iteration to allow M365 action to process..."
        Start-Sleep -Seconds 60

    } while ($ItemsFound -gt 0)

    Write-Log -Message "SUCCESS: Contact deletion process finalized." -Type "SUCCESS"
    exit 0

}
catch {
    Write-Log -Message "FATAL ERROR during Compliance Search or Purge: $($_.Exception.Message)" -Type "ERROR"
    exit 1004
}
finally {
    # 4. Cleanup and Disconnect
    Write-Log -Message "Disconnecting SCC session."
    # Use a check to prevent errors if $Session was never created
    if ($Session -ne $null) {
        Remove-PSSession -Session $Session -ErrorAction SilentlyContinue
    }
    Write-Log -Message "--- Script Execution Finished ---"
}