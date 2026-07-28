# Resilient IT Intune App Deployment Package v1.0.0

This package contains validated Intune deployment scripts for commercial Microsoft 365 tenants and GCC High tenants.

## Package contents

### Global
- iOS App Store application deployment
- Android Enterprise work-profile Managed Google Play application deployment
- Windows Company Portal deployment
- Windows inbox-app removal deployment

### GCC High
- iOS App Store application deployment
- Android Enterprise work-profile Managed Google Play application deployment
- Windows Company Portal deployment
- Windows inbox-app removal deployment

### Common
- Endpoint-side Windows inbox-app removal payload

## Quick start

1. Extract the ZIP file to a technician workstation.
2. Open Windows PowerShell as an administrator.
3. Change to the extracted package directory.
4. Run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\Start-RIT-Intune-App-Deployment.ps1
```

You may also run any deployment script directly from the Global or GCCH folder.

## Authentication

The scripts use Microsoft Graph PowerShell authentication and request the permissions required by each workload. GCC High scripts use the `USGov` environment and `graph.microsoft.us` endpoints.

## Prerequisites

- Microsoft Graph PowerShell modules can be installed from PowerShell Gallery.
- The signed-in account must have sufficient Intune administrative permissions.
- Android Enterprise tenants must already be connected to Managed Google Play.
- Network access to Microsoft Graph, Apple App Store lookup services, and Google Play services must be available as applicable.

## Logging

Deployment scripts write logs and CSV result files to `C:\Temp`.

## Production baseline

The iOS scripts are based on the validated v1.10.x implementation that uses Graph beta only for the iOS assignment property required to set **Prevent iCloud app backup = Yes**.

## Safety behavior

- Existing app objects are detected and reused when possible.
- Duplicate assignments are avoided.
- Unrelated group or user assignments are preserved where supported.
- Windows Store Company Portal is installed in system context.
- Windows inbox-app removal removes matching installed and provisioned Appx packages.
