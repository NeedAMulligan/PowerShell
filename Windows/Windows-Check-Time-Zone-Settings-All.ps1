<#
.SYNOPSIS
    Audits Windows configurations, GPO registry paths, and services that override or disable automatic time zone updates.
#>

$AuditResults = [Ordered]@{
    "AutoTimeZoneServiceStart"  = "OK"
    "LocationPolicyDisabled"     = "OK"
    "CapabilityAccessDisabled"  = "OK"
    "GPO_DisableAutoTimeZone"   = "OK"
    "SensorOverrideDisabled"    = "OK"
}

$IssuesFound = 0

# 1. Check tzautoupdate service startup type (Must be 2 / Automatic)
$tzStart = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate" -Name "Start" -ErrorAction SilentlyContinue).Start
if ($tzStart -ne 2) {
    $AuditResults["AutoTimeZoneServiceStart"] = "MISCONFIGURED: Value is $tzStart (Expected 2). Service is not set to Automatic."
    $IssuesFound++
}

# 2. Check GPO path that explicitly disables auto time zone
# Policy: Computer Configuration > Administrative Templates > System > Time Providers > Configure auto time zone
$gpoTzPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\W32Time\TimeProviders\NtpClient"
$gpoAutoTz = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\International" -Name "AutoTimeZone" -ErrorAction SilentlyContinue).AutoTimeZone
if ($gpoAutoTz -eq 0) {
    $AuditResults["GPO_DisableAutoTimeZone"] = "BLOCKED BY GPO: AutoTimeZone is set to 0 under Software\Policies."
    $IssuesFound++
}

# 3. Check Group Policy/MDM Location Disable Policies
# Policy: Computer Configuration > Administrative Templates > Windows Components > Location and Sensors
$gpoLocationPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
$disableLocation = (Get-ItemProperty -Path $gpoLocationPath -Name "DisableLocation" -ErrorAction SilentlyContinue).DisableLocation
if ($disableLocation -eq 1) {
    $AuditResults["LocationPolicyDisabled"] = "BLOCKED BY GPO: DisableLocation policy is set to 1 under LocationAndSensors."
    $IssuesFound++
}

# 4. Check App Capability / Privacy Consent Store Override
$consentPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
$consentVal = (Get-ItemProperty -Path $consentPath -Name "Value" -ErrorAction SilentlyContinue).Value
if ($consentVal -eq "Deny") {
    $AuditResults["CapabilityAccessDisabled"] = "BLOCKED: Location consent store is set to Deny."
    $IssuesFound++
}

# 5. Check Sensor Permission State Override
$sensorOverridePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}"
$sensorState = (Get-ItemProperty -Path $sensorOverridePath -Name "SensorPermissionState" -ErrorAction SilentlyContinue).SensorPermissionState
if ($sensorState -eq 0) {
    $AuditResults["SensorOverrideDisabled"] = "BLOCKED: Location SensorPermissionState is set to 0."
    $IssuesFound++
}

# Output Summary
Write-Output "=========================================="
Write-Output "     AUTO TIME ZONE AUDIT REPORT          "
Write-Output "=========================================="
foreach ($key in $AuditResults.Keys) {
    Write-Output ("{0,-26} : {1}" -f $key, $AuditResults[$key])
}
Write-Output "------------------------------------------"

if ($IssuesFound -gt 0) {
    Write-Output "RESULT: $IssuesFound conflicting policy/registry setting(s) detected."
    exit 1
} else {
    Write-Output "RESULT: No conflicting GPO or registry overrides detected. Auto time zone should remain enabled."
    exit 0
}