# Hyper-V VM Inventory
# Compatible with Windows PowerShell 5.1
# Supports SYSTEM execution through ScreenConnect Backstage

$OutputDir = 'C:\Temp'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Computer  = $env:COMPUTERNAME

New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null

$CsvPath = Join-Path $OutputDir "HyperV-VM-Inventory-$Computer-$Timestamp.csv"
$LogPath = Join-Path $OutputDir "HyperV-VM-Inventory-$Computer-$Timestamp.txt"

try {
    Import-Module Hyper-V -ErrorAction Stop

    $VMs = @(Get-VM -ErrorAction Stop | Sort-Object Name)

    $Results = @(
        foreach ($VM in $VMs) {
            [PSCustomObject]@{
                VMName         = $VM.Name
                State          = $VM.State.ToString()
                Status         = $VM.Status
                CPUUsage       = $VM.CPUUsage
                MemoryGB       = [math]::Round($VM.MemoryAssigned / 1GB, 2)
                Uptime         = $VM.Uptime.ToString()
                VMId           = $VM.VMId
                Configuration  = $VM.ConfigurationLocation
            }
        }
    )

    $Report = @(
        "========== HYPER-V VM INVENTORY =========="
        "Host       : $Computer"
        "Date       : $(Get-Date)"
        "Total VMs  : $($VMs.Count)"
        "Running    : $( @($VMs | Where-Object { $_.State -eq 'Running' }).Count )"
        "Powered Off: $( @($VMs | Where-Object { $_.State -eq 'Off' }).Count )"
        "=========================================="
        ""
        ($Results | Format-Table VMName, State, Status, CPUUsage, MemoryGB -AutoSize | Out-String -Width 240)
        ""
        "CSV Output : $CsvPath"
        "Text Output: $LogPath"
    ) -join "`r`n"

    $Report | Out-File -FilePath $LogPath -Encoding UTF8
    Write-Output $Report

    if ($Results.Count -gt 0) {
        $Results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    }
    else {
        Write-Output "No virtual machines registered on this host."
    }
}
catch {
    $ErrorMessage = "ERROR querying Hyper-V host $Computer : $($_.Exception.Message)"
    Write-Output $ErrorMessage
    $ErrorMessage | Out-File -FilePath $LogPath -Encoding UTF8
    exit 1
}