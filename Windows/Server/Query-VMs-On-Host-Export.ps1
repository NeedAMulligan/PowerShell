# Hyper-V VM Inventory Export
# Windows PowerShell 5.1
# Read-only - does not modify VMs

$OutputDir = 'C:\Temp'
$HostName = $env:COMPUTERNAME
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null

$CsvFile = "$OutputDir\HyperV-VMs-$HostName-$Timestamp.csv"
$TxtFile = "$OutputDir\HyperV-VMs-$HostName-$Timestamp.txt"

try {
    Import-Module Hyper-V -ErrorAction Stop

    $VMs = @(
        Get-VM -ErrorAction Stop |
        Sort-Object Name |
        Select-Object Name, State, Status, CPUUsage,
            @{Name='MemoryGB';Expression={
                [math]::Round($_.MemoryAssigned / 1GB, 2)
            }},
            Uptime, VMId
    )

    # Export CSV
    $VMs | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8

    # Export readable TXT
    $VMs |
        Format-Table Name, State, Status, CPUUsage, MemoryGB, Uptime -AutoSize |
        Out-String -Width 240 |
        Out-File -FilePath $TxtFile -Encoding UTF8

    # Display results in ScreenConnect
    Write-Output "Hyper-V Host: $HostName"
    Write-Output "Total VMs: $($VMs.Count)"
    Write-Output ""
    $VMs | Format-Table Name, State, Status -AutoSize

    Write-Output ""
    Write-Output "CSV: $CsvFile"
    Write-Output "TXT: $TxtFile"
}
catch {
    Write-Error "Hyper-V inventory failed: $($_.Exception.Message)"
    exit 1
}