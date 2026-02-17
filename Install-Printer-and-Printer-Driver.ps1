<#
.SYNOPSIS
    Unzips and installs the Toshiba Universal Printer 2 locally.
.DESCRIPTION
    1. Unzips the driver package to C:\temp.
    2. Cleans up existing printers/ports on 10.1.10.30.
    3. Registers the driver and creates the printer object.
#>

Function Install-ToshibaPrinterLocal {
    [CmdletBinding()]
    Param(
        [string]$ZipPath      = "C:\temp\ebn-Uni-7.222.5412.313.zip",
        [string]$ExtractPath  = "C:\temp",
        [string]$PrinterName  = "Toshiba Office Printer",
        [string]$PrinterIP    = "10.1.10.30",
        [string]$DriverName   = "TOSHIBA Universal Printer 2",
        # This path is based on your previous confirmation of the nested structure
        [string]$InfSubPath   = "ebn-Uni-7.222.5412.313\UNI\Driver\64bit\eSf6u.inf"
    )

    Process {
        Write-Host "--- Initializing Local Printer Setup ---" -ForegroundColor Cyan

        try {
            # 1. Unzip the Driver Folder
            if (Test-Path $ZipPath) {
                Write-Host "[1/5] Unzipping driver package..." -NoNewline
                # Force parameter ensures we overwrite any existing folder from a failed run
                Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force -ErrorAction Stop
                Write-Host " SUCCESS" -ForegroundColor Green
            } else {
                throw "Zip file not found at $ZipPath. Ensure your RMM uploaded it correctly."
            }

            $FullInfPath = Join-Path $ExtractPath $InfSubPath

            # 2. Port and Printer Cleanup
            Write-Host "[2/5] Cleaning existing 10.1.10.30 configurations..." -NoNewline
            $ExistingPrinters = Get-Printer | Where-Object { $_.PortName -eq $PrinterIP }
            foreach ($P in $ExistingPrinters) {
                Remove-Printer -Name $P.Name -ErrorAction SilentlyContinue
            }

            if (Get-PrinterPort -Name $PrinterIP -ErrorAction SilentlyContinue) {
                Remove-PrinterPort -Name $PrinterIP -ErrorAction Stop
                Write-Host " CLEANED" -ForegroundColor Green
            } else {
                Write-Host " CLEAR" -ForegroundColor Green
            }

            # 3. Recreate the Printer Port
            Write-Host "[3/5] Creating Port at $PrinterIP..." -NoNewline
            Add-PrinterPort -Name $PrinterIP -PrinterHostAddress $PrinterIP -ErrorAction Stop
            Write-Host " SUCCESS" -ForegroundColor Green

            # 4. Register Driver with Spooler
            Write-Host "[4/5] Registering Driver: $DriverName..." -NoNewline
            # Staging with PNPUtil first to ensure the Driver Store has it
            pnputil.exe /add-driver "$FullInfPath" /install | Out-Null
            
            # Registering the name with the Spooler
            Add-PrinterDriver -Name $DriverName -InfPath $FullInfPath -ErrorAction Stop
            Write-Host " SUCCESS" -ForegroundColor Green

            # 5. Create the Printer Object
            Write-Host "[5/5] Creating Printer: $PrinterName..." -NoNewline
            Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PrinterIP -ErrorAction Stop
            Write-Host " SUCCESS" -ForegroundColor Green

            Write-Host "`nSetup successfully finished! Your printer is ready." -ForegroundColor White
        }
        catch {
            Write-Error "Setup failed: $($_.Exception.Message)"
        }
    }
}

# --- Admin Check and Execution ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run as Administrator!"
} else {
    Install-ToshibaPrinterLocal
}