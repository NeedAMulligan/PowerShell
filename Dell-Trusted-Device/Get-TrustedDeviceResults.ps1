<#PSScriptInfo
.VERSION 1.0.0
.GUID e4e18caa-4472-4f3d-ae88-d3d6fec9f8a1
.AUTHOR Dell Trusted Device
.COMPANYNAME Dell Technologies, Inc.
.COPYRIGHT (c) Copyright 2021-2024, Dell Inc., All Rights Reserved.
.TAGS
.LICENSEURI
.PROJECTURI
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
.PRIVATEDATA
#>

<#
.DESCRIPTION
 Inspects the Dell Trusted Device installation and components and returns a JSON object detailing the state of the product.
 Script Execution Status:
    - (bool) Script executed without exceptions
    - (string) Script exception message

Install Details:
    - Product installation
        - (bool) is the product installed
        - (string) product version

    - DTD Service
        - (bool) is the DTD service installed
        - (string) DTD service file version
        - (bool) DTD service executable is signed by Dell with a valid signature
        - (bool) DTD service state is set to RUNNING
        - (bool) DTD service start type is AUTO_START
        - (string) DTD service can be stopped by non-System users ("yes", "no", "unknown")

    - DTD SEL Driver
        - (bool) dtdsel driver is installed
        - (string) dtdsel driver file version
        - (bool) dtdsel driver is signed by Dell with a valid signature
        - (bool) dtdsel driver state is set to RUNNING
        - (bool) dtdsel driver start type is SYSTEM_START

    - Dell BV Driver
        - (bool) dellbv driver is installed
        - (string) dellbv driver file version
        - (bool) dellbv driver is signed by Dell with a valid signature
        - (bool) dellbv driver start type is DEMAND_START

    - Bios Verification Result
        - (bool) BV result is available
        - (string) BV result source name ("unknown", "service", "registry", "filesystem")
        - (bool) BV result source is valid
        - (bool) BV result itself
        - (int) BV processing error code (Not available for Registry and File BV results)
        - (int) BV result age in days
        - (bool) BV result indicated that the tampering was detected
        - (bool) BV result indicated that the BIOS is invalid
        - (bool) BV result indicated that the BIOS is not supported
        - (bool) BV result indicated that a client error occurred
        - (bool) BV result indicated that a server error occurred

    - Intel ME Verification Result
        - (bool) MEV result is available
        - (string) MEV result source name ("service")
        - (bool) MEV result source is valid
        - (bool) MEV result itself
        - (int) MEV processing error code (Not available for Registry and File BV results)
        - (int) MEV result age in days
        - (bool) MEV result indicated that the tampering was detected
        - (bool) MEV result indicated that the BIOS is invalid
        - (bool) MEV result indicated that the BIOS is not supported
        - (bool) MEV result indicated that a client error occurred
        - (bool) MEV result indicated that a server error occurred

    - Secured Component Verification Result
        - (bool) SCV result is available
        - (string) SCV result source name ("service")
        - (bool) SCV result source is valid
        - (bool) SCV result itself
        - (int) SCV processing error code (Not available for Registry and File BV results)
        - (int) SCV result age in days
        - (bool) SCV result indicated that the tampering was detected
        - (bool) SCV result indicated that the BIOS is invalid
        - (bool) SCV result indicated that the BIOS is not supported
        - (bool) SCV result indicated that a client error occurred
        - (bool) SCV result indicated that a server error occurred

    - CVE Correlation Result
        - (bool) CVE Correlation result is available
        - (string) CVE Correlation result source name ("service")
        - (bool) CVE Correlation result source is valid
        - (bool) CVE Correlation result itself
        - (int) CVE Correlation processing error code (Not available for Registry and File BV results)
        - (int) CVE Correlation result age in days
        - (bool) CVE Correlation result indicated that the tampering was detected
        - (bool) CVE Correlation result indicated that the BIOS is invalid
        - (bool) CVE Correlation result indicated that the BIOS is not supported
        - (bool) CVE Correlation result indicated that a client error occurred
        - (bool) CVE Correlation result indicated that a server error occurred
        - (double) CVE Correlation result highest vulnerability score
        - (int) CVE Correlation result number of critical vulnerabilities
        - (int) CVE Correlation result number of high vulnerabilities
        - (int) CVE Correlation result number of medium vulnerabilities
        - (int) CVE Correlation result number of low vulnerabilities
        - (bool) CVE Correlation result indicated that the BIOS is out of date
    

Example Output:
{
    "ScriptExecutedWithoutExceptions": true,
    "ScriptExceptionMessage": "",

    "DtdProductInstalled":  true,
    "DtdProductVersion":  "3.5.639",

    "DtdServiceInstalled":  true,
    "DtdServiceVersion":  "3.5.672.0",
    "DtdServiceIsSignatureValid":  true,
    "DtdServiceIsRunning":  true,
    "DtdServiceIsAutoStart":  true,
    "DtdServiceIsStoppable":  "no",

    "DtdSelDriverInstalled":  true,
    "DtdSelDriverVersion":  "3.4.610.0",
    "DtdSelDriverSignatureIsValid":  true,
    "DtdSelDriverIsRunning":  true,
    "DtdSelDriverIsSystemStart":  true,

    "DellBvDriverInstalled":  true,
    "DellBvDriverVersion":  "3.4.610.0",
    "DellBvDriverSignatureIsValid":  true,
    "DellBvDriverIsDemandStart":  true,

    "BvResultAvailable": true,
    "BvResultSourceName": "service",
    "BvResultSourceIsValid": true,
    "BvResult": true,
    "BvResultErrorCode": 0,
    "BvResultAgeInDays": 1
    "BvResultIndicatesTampering": false,
    "BvResultBiosIsInvalid": false,
    "BvResultBiosNotSupported": false,
    "BvResultClientErrorOccurred": false,
    "BvResultServerErrorOccurred": false,

    "MEvResultAvailable": true,
    "MEvResultSourceName": "service",
    "MEvResultSourceIsValid": true,
    "MEvResult": true,
    "MEvResultErrorCode": 0,
    "MEvResultAgeInDays": 1
    "MEvResultIndicatesTampering": false,
    "MEvResultMEIsInvalid": false,
    "MEvResultMENotSupported": false,
    "MEvResultClientErrorOccurred": false,
    "MEvResultServerErrorOccurred": false,

    "SCvResultAvailable": true,
    "SCvResultSourceName": "service",
    "SCvResultSourceIsValid": true,
    "SCvResult": true,
    "SCvResultErrorCode": 0,
    "SCvResultAgeInDays": 1
    "SCvResultIndicatesTampering": false,
    "SCvResultIsInvalid": false,
    "SCvResultNotSupported": false,
    "SCvResultClientErrorOccurred": false,
    "SCvResultServerErrorOccurred": false,

    "CveResultAvailable": true,
    "CveResultSourceName": "service",
    "CveResultSourceIsValid": true,
    "CveResult": true,
    "CveResultErrorCode": 0,
    "CveResultAgeInDays": 1
    "CveResultIndicatesTampering": false,
    "CveResultBiosIsInvalid": false,
    "CveResultBiosNotSupported": false,
    "CveResultClientErrorOccurred": false,
    "CveResultServerErrorOccurred": false,
    "CveHighestScore": 0.0,
    "CveCriticalCount": 0,
    "CveHighCount": 0,
    "CveMediumCount": 0,
    "CveLowCount": 0,
    "BiosOutOfDate": false
}
#>

# Require PowerShell 5.1
#Requires -Version 5.1

# Contains the full set of information about the DTD product installation, including service and driver details
# This class is serialized to JSON as the main output from this script.
class DtdFullDetails {
    # Script executed without exceptions
    [ValidateNotNullOrEmpty()][bool]$ScriptExecutedWithoutExceptions
    [string]$ScriptExceptionMessage

    # DTD product details
    [ValidateNotNullOrEmpty()][bool]$DtdProductInstalled
    [string]$DtdProductVersion

    # DTD service details
    [ValidateNotNullOrEmpty()][bool]$DtdServiceInstalled
    [string]$DtdServiceVersion
    [bool]$DtdServiceIsSignatureValid
    [bool]$DtdServiceIsRunning
    [bool]$DtdServiceIsAutoStart
    [string]$DtdServiceIsStoppable

    # DTD secure event log driver details
    [ValidateNotNullOrEmpty()][bool]$DtdSelDriverInstalled
    [string]$DtdSelDriverVersion
    [bool]$DtdSelDriverSignatureIsValid
    [bool]$DtdSelDriverIsRunning
    [bool]$DtdSelDriverIsSystemStart

    # DTD bios verification driver details
    [ValidateNotNullOrEmpty()][bool]$DellBvDriverInstalled
    [string]$DellBvDriverVersion
    [bool]$DellBvDriverSignatureIsValid
    [bool]$DellBvDriverIsDemandStart

    # DTD bios verification result details
    [ValidateNotNullOrEmpty()][bool]$BvResultAvailable
    [string]$BvResultSourceName
    [bool]$BvResultSourceIsValid
    [bool]$BvResult
    [int]$BvResultErrorCode
    [int]$BvResultAgeInDays
    [bool]$BvResultIndicatesTampering
    [bool]$BvResultBiosIsInvalid
    [bool]$BvResultBiosNotSupported
    [bool]$BvResultClientErrorOccurred
    [bool]$BvResultServerErrorOccurred

    # DTD ME verification result details
    [ValidateNotNullOrEmpty()][bool]$MEvResultAvailable
    [string]$MEvResultSourceName
    [bool]$MEvResultSourceIsValid
    [bool]$MEvResult
    [int]$MEvResultErrorCode
    [int]$MEvResultAgeInDays
    [bool]$MEvResultIndicatesTampering
    [bool]$MEvResultMEIsInvalid
    [bool]$MEvResultMENotSupported
    [bool]$MEvResultClientErrorOccurred
    [bool]$MEvResultServerErrorOccurred

    # DTD Secured Component Verification result details
    [ValidateNotNullOrEmpty()][bool]$SCvResultAvailable
    [string]$SCvResultSourceName
    [bool]$SCvResultSourceIsValid
    [bool]$SCvResult
    [int]$SCvResultErrorCode
    [int]$SCvResultAgeInDays
    [bool]$SCvResultIndicatesTampering
    [bool]$SCvResultIsInvalid
    [bool]$SCvResultNotSupported
    [bool]$SCvResultClientErrorOccurred
    [bool]$SCvResultServerErrorOccurred

    # DTD CVE Correlation result details
    [ValidateNotNullOrEmpty()][bool]$CveResultAvailable
    [string]$CveResultSourceName
    [bool]$CveResultSourceIsValid
    [bool]$CveResult
    [int]$CveResultErrorCode
    [int]$CveResultAgeInDays
    [bool]$CveResultIndicatesTampering
    [bool]$CveResultBiosIsInvalid
    [bool]$CveResultBiosNotSupported
    [bool]$CveResultClientErrorOccurred
    [bool]$CveResultServerErrorOccurred
    [double]$CveHighestScore
    [int]$CveCriticalCount
    [int]$CveHighCount
    [int]$CveMediumCount
    [int]$CveLowCount
    [bool]$BiosOutOfDate
    [bool]$FirmwareOutOfDate

    # Default constructor
    DtdFullDetails() {
        $this.ScriptExecutedWithoutExceptions = $false
        $this.ScriptExceptionMessage = ""

        $this.DtdProductInstalled = $false
        $this.DtdProductVersion = ""

        $this.DtdServiceInstalled = $false
        $this.DtdServiceVersion = ""
        $this.DtdServiceIsSignatureValid = $false
        $this.DtdServiceIsRunning = $false
        $this.DtdServiceIsAutoStart = $false
        $this.DtdServiceIsStoppable = "unknown"     # Default value should indicate non-compliance

        $this.DtdSelDriverInstalled = $false
        $this.DtdSelDriverVersion = ""
        $this.DtdSelDriverSignatureIsValid = $false
        $this.DtdSelDriverIsSystemStart = $false

        $this.DellBvDriverInstalled = $false
        $this.DellBvDriverVersion = ""
        $this.DellBvDriverSignatureIsValid = $false
        $this.DellBvDriverIsDemandStart = $false

        $this.BvResultAvailable = $false
        $this.BvResultSourceName = "unknown"    # Default value should indicate non-compliance
        $this.BvResultSourceIsValid = $false
        $this.BvResult = $false
        $this.BvResultErrorCode = 11
        $this.BvResultAgeInDays = 0
        $this.BvResultIndicatesTampering = $false
        $this.BvResultBiosIsInvalid = $false
        $this.BvResultBiosNotSupported = $true
        $this.BvResultClientErrorOccurred = $false
        $this.BvResultServerErrorOccurred = $false

        $this.MEvResultAvailable = $false
        $this.MEvResultSourceName = "unknown"    # Default value should indicate non-compliance
        $this.MEvResultSourceIsValid = $false
        $this.MEvResult = $false
        $this.MEvResultErrorCode = 11
        $this.MEvResultAgeInDays = 0
        $this.MEvResultIndicatesTampering = $false
        $this.MEvResultMEIsInvalid = $false
        $this.MEvResultMENotSupported = $true
        $this.MEvResultClientErrorOccurred = $false
        $this.MEvResultServerErrorOccurred = $false

        $this.SCvResultAvailable = $false
        $this.SCvResultSourceName = "unknown"    # Default value should indicate non-compliance
        $this.SCvResultSourceIsValid = $false
        $this.SCvResult = $false
        $this.SCvResultErrorCode = 11
        $this.SCvResultAgeInDays = 0
        $this.SCvResultIndicatesTampering = $false
        $this.SCvResultIsInvalid = $false
        $this.SCvResultNotSupported = $true
        $this.SCvResultClientErrorOccurred = $false
        $this.SCvResultServerErrorOccurred = $false

        $this.CveResultAvailable = $false
        $this.CveResultSourceName = "unknown"    # Default value should indicate non-compliance
        $this.CveResultSourceIsValid = $false
        $this.CveResult = $false
        $this.CveResultErrorCode = 11
        $this.CveResultAgeInDays = 0
        $this.CveResultIndicatesTampering = $false
        $this.CveResultBiosIsInvalid = $false
        $this.CveResultBiosNotSupported = $true
        $this.CveResultClientErrorOccurred = $false
        $this.CveResultServerErrorOccurred = $false
        $this.CveHighestScore = 0.0
        $this.CveCriticalCount = 0
        $this.CveHighCount = 0
        $this.CveMediumCount = 0
        $this.CveLowCount = 0
        $this.BiosOutOfDate = $false
        $this.FirmwareOutOfDate = $false
    }
}

# Contains details for an installation of DTD
class DtdProductDetails {
    # True if the DTD Product is installed in the registry
    [ValidateNotNullOrEmpty()][bool]$IsInstalled

    # DTD installation directory from the registry
    [string]$InstallDir

    # DTD *installer* product version from the registry
    [string]$Version

    # Default constructor
    DtdProductDetails([bool]$isInstalled, [string]$installDir, [string]$version) {
        $this.IsInstalled = $isInstalled
        $this.InstallDir = $installDir
        $this.Version = $version
    }
}

# Contains details for a DTD executable (either a service or driver)
class DtdExecutable {
    # True if the executable is installed in the registry
    [ValidateNotNullOrEmpty()][bool]$IsInstalled

    # File version of the executable retrieved from its file details
    [string]$Version

    # True if the executable has a valid Dell signature
    [bool]$SignatureIsValid

    # True if the executable is currently running
    [bool]$IsRunning

    # Default constructor
    DtdExecutable([bool]$isInstalled, [string]$version, [bool]$signatureIsValid, [bool]$isRunning) {
        $this.IsInstalled = $isInstalled
        $this.Version = $version
        $this.SignatureIsValid = $signatureIsValid
        $this.IsRunning = $isRunning
    }
}

# Contains details for the DTD service
class DtdServiceDetails : DtdExecutable {
    # True if the service is set to automatically start
    [bool]$IsAutoStart

    # "yes" if the service was installed with the ability to manually stop it
    [string]$IsStoppable

    # Default constructor
    DtdServiceDetails([bool]$isAutoStart, [string]$isStoppable, [bool]$isInstalled, [string]$version, [bool]$signatureIsValid, [bool]$isRunning)
    : base($isInstalled, $version, $signatureIsValid, $isRunning) {
        $this.IsAutoStart = $isAutoStart
        $this.IsStoppable = $isStoppable
    }
}

# Contains details for the DTD SEL driver (dtdsel)
class DtdSelDriverDetails : DtdExecutable {
    # True if the dtdsel driver is set to start when the system starts
    [bool]$IsSystemStart

    # Default constructor
    DtdSelDriverDetails([bool]$isSystemStart, [bool]$isInstalled, [string]$version, [bool]$signatureIsValid, [bool]$isRunning)
    : base($isInstalled, $version, $signatureIsValid, $isRunning) {
        $this.IsSystemStart = $isSystemStart
    }
}

# Contains details for the DTD BV driver (dellbv)
class DellBvDriverDetails : DtdExecutable {
    # True if the dellbv driver is set to be manually started
    [bool]$IsManualStart

    # Default constructor
    DellBvDriverDetails([bool]$isManualStart, [bool]$isInstalled, [string]$version, [bool]$signatureIsValid, [bool]$isRunning)
    : base($isInstalled, $version, $signatureIsValid, $isRunning) {
        $this.IsManualStart = $isManualStart
    }
}

# Contains details for the Bios Verification Result
class DtdBvResultDetails {
    # True if the result was available
    [bool]$IsAvailable

    # Contains the result source name ("unknown", "service", "registry", or "filesystem")
    [string]$SourceName

    # True if the result passed signature validation
    [bool]$SourceIsValid

    # True if the result indicates that bios verification succeeded
    [bool]$Outcome

    # Contains the error code, if available. if not available, 0 is used
    [int]$ErrorCode

    # Contains the result age in days
    [int]$AgeInDays

    # True if tampering was detected while processing the result
    [bool]$TamperingDetected

    # True if the BIOS is invalid
    [bool]$BiosIsInvalid

    # True if the BIOS is not supported
    [bool]$BiosNotSupported

    # True if an error occurred on the client
    [bool]$ClientErrorOccurred

    # True if an error occurred on the server
    [bool]$ServerErrorOccurred

    # Default constructor
    DtdBvResultDetails(
        [bool]$isAvailable, [bool]$sourceIsValid, [bool]$outcome, [int]$errorCode, [int]$ageInDays, [string]$sourceName,
        [bool]$tamperingDetected, [bool]$biosIsInvalid, [bool]$biosNotSupported,
        [bool]$clientErrorOccurred, [bool]$serverErrorOccurred
        ) {
        $this.IsAvailable = $isAvailable
        $this.SourceName = $sourceName
        $this.SourceIsValid = $sourceIsValid
        $this.Outcome = $outcome
        $this.ErrorCode = $errorCode
        $this.AgeInDays = $ageInDays
        $this.TamperingDetected = $tamperingDetected
        $this.BiosIsInvalid = $biosIsInvalid
        $this.BiosNotSupported = $biosNotSupported
        $this.ClientErrorOccurred = $clientErrorOccurred
        $this.ServerErrorOccurred = $serverErrorOccurred
    }
}

# Contains details for the Intel ME Verification Result
class DtdMEvResultDetails {
    # True if the result was available
    [bool]$IsAvailable

    # Contains the result source name ("unknown", "service", "registry", or "filesystem")
    [string]$SourceName

    # True if the result passed signature validation
    [bool]$SourceIsValid

    # True if the result indicates that ME verification succeeded
    [bool]$Outcome

    # Contains the error code, if available. if not available, 2 is used
    [int]$ErrorCode

    # Contains the result age in days
    [int]$AgeInDays

    # True if tampering was detected while processing the result
    [bool]$TamperingDetected

    # True if the Intel ME is invalid
    [bool]$MeIsInvalid

    # True if the Intel ME is not supported
    [bool]$MeNotSupported

    # True if an error occurred on the client
    [bool]$ClientErrorOccurred

    # True if an error occurred on the server
    [bool]$ServerErrorOccurred

    # Default constructor
    DtdMEvResultDetails(
        [bool]$isAvailable, [bool]$sourceIsValid, [bool]$outcome, [int]$errorCode, [int]$ageInDays, [string]$sourceName,
        [bool]$tamperingDetected, [bool]$meIsInvalid, [bool]$meNotSupported,
        [bool]$clientErrorOccurred, [bool]$serverErrorOccurred
        ) {
        $this.IsAvailable = $isAvailable
        $this.SourceName = $sourceName
        $this.SourceIsValid = $sourceIsValid
        $this.Outcome = $outcome
        $this.ErrorCode = $errorCode
        $this.AgeInDays = $ageInDays
        $this.TamperingDetected = $tamperingDetected
        $this.MeIsInvalid = $meIsInvalid
        $this.MeNotSupported = $meNotSupported
        $this.ClientErrorOccurred = $clientErrorOccurred
        $this.ServerErrorOccurred = $serverErrorOccurred
    }
}

# Contains details for the Secured Component Verification Result
class DtdScvResultDetails {
    # True if the result was available
    [bool]$IsAvailable

    # Contains the result source name ("unknown", "service", "registry", or "filesystem")
    [string]$SourceName

    # True if the result passed signature validation
    [bool]$SourceIsValid

    # True if the result indicates that ME verification succeeded
    [bool]$Outcome

    # Contains the error code, if available. if not available, 2 is used
    [int]$ErrorCode

    # Contains the result age in days
    [int]$AgeInDays

    # True if tampering was detected while processing the result
    [bool]$TamperingDetected

    # True if the Intel ME is invalid
    [bool]$ScvIsInvalid

    # True if the Intel ME is not supported
    [bool]$ScvNotSupported

    # True if an error occurred on the client
    [bool]$ClientErrorOccurred

    # True if an error occurred on the server
    [bool]$ServerErrorOccurred

    # Default constructor
    DtdScvResultDetails(
        [bool]$isAvailable, [bool]$sourceIsValid, [bool]$outcome, [int]$errorCode, [int]$ageInDays, [string]$sourceName,
        [bool]$tamperingDetected, [bool]$scvIsInvalid, [bool]$scvNotSupported,
        [bool]$clientErrorOccurred, [bool]$serverErrorOccurred
        ) {
        $this.IsAvailable = $isAvailable
        $this.SourceName = $sourceName
        $this.SourceIsValid = $sourceIsValid
        $this.Outcome = $outcome
        $this.ErrorCode = $errorCode
        $this.AgeInDays = $ageInDays
        $this.TamperingDetected = $tamperingDetected
        $this.ScvIsInvalid = $scvIsInvalid
        $this.ScvNotSupported = $scvNotSupported
        $this.ClientErrorOccurred = $clientErrorOccurred
        $this.ServerErrorOccurred = $serverErrorOccurred
    }
}

# Contains details for the CVE Correlation Result
class DtdCveResultDetails {
    # True if the result was available
    [bool]$IsAvailable

    # Contains the result source name ("unknown", "service", "registry", or "filesystem")
    [string]$SourceName

    # True if the result passed signature validation
    [bool]$SourceIsValid

    # True if the result indicates that CVE Correlation succeeded
    [bool]$Outcome

    # Contains the error code, if available. if not available, 0 is used
    [int]$ErrorCode

    # Contains the result age in days
    [int]$AgeInDays

    # True if tampering was detected while processing the result
    [bool]$TamperingDetected

    # True if the BIOS is invalid
    [bool]$BiosIsInvalid

    # True if the BIOS is not supported
    [bool]$BiosNotSupported

    # True if an error occurred on the client
    [bool]$ClientErrorOccurred

    # True if an error occurred on the server
    [bool]$ServerErrorOccurred

    # Contains the highest vulnerability score
    [double]$CveHighestScore

    # Contains the number of critical vulnerabilities
    [int]$CriticalVulnerabilityCount

    # Contains the number of high vulnerabilities
    [int]$HighVulnerabilityCount

    # Contains the number of medium vulnerabilities
    [int]$MediumVulnerabilityCount

    # Contains the number of low vulnerabilities
    [int]$LowVulnerabilityCount

    # True if the BIOS is out of date
    [bool]$BiosOutOfDate

    # True if the Firmware is out of date
    [bool]$FirmwareOutOfDate

    # Default constructor
    DtdCveResultDetails(
        [bool]$isAvailable, [bool]$sourceIsValid, [bool]$outcome, [int]$errorCode, [int]$ageInDays, [string]$sourceName,
        [bool]$tamperingDetected, [bool]$biosIsInvalid, [bool]$biosNotSupported,
        [bool]$clientErrorOccurred, [bool]$serverErrorOccurred, [double]$CveHighestScore,
        [int]$criticalVulnerabilityCount, [int]$highVulnerabilityCount, [int]$mediumVulnerabilityCount, [int]$lowVulnerabilityCount,
        [bool]$biosOutOfDate, [bool]$firmwareOutOfDate
        ) {
        $this.IsAvailable = $isAvailable
        $this.SourceName = $sourceName
        $this.SourceIsValid = $sourceIsValid
        $this.Outcome = $outcome
        $this.ErrorCode = $errorCode
        $this.AgeInDays = $ageInDays
        $this.TamperingDetected = $tamperingDetected
        $this.BiosIsInvalid = $biosIsInvalid
        $this.BiosNotSupported = $biosNotSupported
        $this.ClientErrorOccurred = $clientErrorOccurred
        $this.ServerErrorOccurred = $serverErrorOccurred
        $this.CveHighestScore = $CveHighestScore
        $this.CriticalVulnerabilityCount = $criticalVulnerabilityCount
        $this.HighVulnerabilityCount = $highVulnerabilityCount
        $this.MediumVulnerabilityCount = $mediumVulnerabilityCount
        $this.LowVulnerabilityCount = $lowVulnerabilityCount
        $this.BiosOutOfDate = $biosOutOfDate
        $this.FirmwareOutOfDate = $firmwareOutOfDate
    }
}

# Contains Plugin IPC Result information
class DtdPluginIpcResultInfo {
    # BV Result content
    [string]$ResultJson

    # Error code returned for the plugin processing
    [int]$ErrorCode

    # Default constructor
    DtdPluginIpcResultInfo([string]$resultJson, [int]$errorCode) {
        $this.ResultJson = $resultJson
        $this.ErrorCode = $errorCode
    }
}

# Tells the target object or class to invoke the specified method.
# This exists to facilitate unit tests through mocks
function Invoke-Method {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [object]$targetObject,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        [bool]$isStaticMethod,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 2)]
        [string]$methodName,
        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            Position = 3)]
        [object[]]$arguments
    )

    process {
        ##$tgtObjType = $targetObject.GetType()
        ##Write-Warning "Invoking ${methodName} on ${tgtObjType}..."

        # Handle methods with no arguments
        if ($null -eq $arguments) {
            $arguments = @()
        }

        # Dynamically call the specified method on the provided object
        if ($true -eq $isStaticMethod) {
            $targetObject::$MethodName.Invoke($arguments)
        }
        else {
            $targetObject.$MethodName.Invoke($arguments)
        }
    }
}

# Wrapper function around parsing a date/time string
# This exists to facilitate unit tests through mocks
function Get-DateTimeFromString {
    [CmdletBinding()]
    [OutputType([DateTime])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$dateString,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        [string]$formatString
    )

    process {
        try {
            [DateTime]::ParseExact($dateString, $formatString, $null)
        } catch {
            try {
                [DateTime]::ParseExact($dateString, "MM/dd/yyyy hh:mm:ss tt", $null)
            } catch {
                try {
                    [DateTime]::ParseExact($dateString, "MM/dd/yyyy HH:mm:ss", $null)
                } catch {
                    throw "Unable to parse date/time string: ${dateString} with format ${formatString}"
                }
            }
        }
    }
}

# Wrapper function around retrieving the FileVersion for a binary
# This exists to facilitate unit tests through mocks
function Get-FileVersionWrapper {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$binaryPath
    )

    process {
        # For some reason, our drivers don't seem to publish the entire version string
        #   in a manner compatible with the FileVersion property,
        #   so we rebuild the version number from its component parts.
        $majorPart = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($binaryPath).FileMajorPart
        $minorPart = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($binaryPath).FileMinorPart
        $buildPart = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($binaryPath).FileBuildPart
        $privatePart = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($binaryPath).FilePrivatePart

        "${majorPart}.${minorPart}.${buildPart}.${privatePart}"
    }
}

# Wrapper function around acquiring the signing cert for a binary
# This exists to facilitate unit tests through mocks
function Get-SigningCertForBinary {
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$binaryPath
    )

    process {
        $certV1 = [System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($binaryPath)
        New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certV1)
    }
}

# Wrapper function around retrieving the thumbprint from a certificate
# This exists to facilitate unit tests through mocks
function Get-ThumbprintFromCert {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$certificate
    )

    process {
        $certificate.GetCertHashString("SHA256")
    }
}

# Function that retrieves the Authenticode signature and verifies the signing certificate's thumbprint
function Get-DellSignatureValidity {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$binaryPath
    )

    begin {
        # Dell SHA256 cert hash strings
        $dellSha256CertHashStrings = @(
            "E02AC3B8CA81E1923FE5285185C5F9E778DF90A17A23E9183067C76B1C61E812",
            "7B12871A8260F6D92123948FC987CF8C82553BAF3047C8264B41D5AA059541AA",
            "6F9B0932CFC3AA6FACD3A1E84D1999C0EE72BE6594211E310F250E3435DD6898",
            "3438EC145486DB5399B555DD8EB3223A85E3F9B0FD82ECD8AA72F3EC6643D3BC"
        )
    }

    process {
        # Start off by verifying the most recent signature on the binary, which will be ours for the service,
        #   but will be Microsoft's for our drivers.
        $signature = Get-AuthenticodeSignature -FilePath $binaryPath
        if ($null -ne $signature -and $signature.Status -eq "Valid") {
            # Acquire a cert from the signed binary and use it to verify that *OUR* signature is present and valid
            $cert = Get-SigningCertForBinary($binaryPath)

            if ($null -ne $cert) {
                $certHashString = Get-ThumbprintFromCert($cert)

                # Compare thumprints to ensure that our cert was used for the primary signature
                if ($dellSha256CertHashStrings.Contains($certHashString)) {
                    return $true
                }
                else {
                    Write-Warning "Binary does not contain accepted signature: ${binaryPath}"
                    Write-Warning "Expected '$($dellSha256CertHashStrings -Join ", ")', but got '${certHashString}'"
                }
            }
            else {
                Write-Warning "Certificate validation failed for binary: ${binaryPath}"
            }
        }
        else {
            Write-Warning "Authenticode validation failed for binary: ${binaryPath}"
        }

        return $false
    }
}

# Wrapper function around converting a binary security descriptor into a raw security descriptor object
# This exists to facilitate unit tests through mocks
function Get-RawSecurityDescriptorFromBinaryData {
    [CmdletBinding()]
    [OutputType([System.Security.AccessControl.RawSecurityDescriptor])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [byte[]]$binaryData
    )

    process {
        New-Object System.Security.AccessControl.RawSecurityDescriptor($binaryData, 0)
    }
}

# Function that determines if a specified service is stoppable based on its DACL
function Get-ServiceIsStoppable {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$serviceShortName
    )

    begin {
        # Constant indicating the service stop access right
        $serviceStopAccessRight = 0x0020

        # SID for the System account
        $systemSid = (New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid), $null)

        # Acquire the security descriptor from the registry
        $serviceSecurityRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\${serviceShortName}\Security"
    }

    process {
        # Track whether or not the service is stoppable by non-System users
        # Default value is a string containing the word "unknown" to indicate that a positive determination could not be made.
        $stoppableByNonSystemUsers = "unknown"

        # Verify that the key path exists
        if (Test-Path $serviceSecurityRegPath) {
            # Acquire the security descriptor from the registry
            $registrySecurityDescriptor = Get-ItemPropertyValue -Path $serviceSecurityRegPath -Name "Security"

            if ($null -ne $registrySecurityDescriptor) {
                # Convert the registry value into a raw security descriptor
                $rawSecurityDescriptor = Get-RawSecurityDescriptorFromBinaryData($registrySecurityDescriptor)

                # Check each entry in the DACL to verify that the stop service access right is denied to everyone except the System account
                if ($rawSecurityDescriptor.DiscretionaryAcl.Count -gt 0) {
                    $stopAceExists = $false

                    $rawSecurityDescriptor.DiscretionaryAcl | ForEach-Object -Process {
                        if ($systemSid -ne $_.SecurityIdentifier -and $_.AceType -eq 'AccessAllowed' -and $serviceStopAccessRight -band $_.AccessMask) {
                            Write-Warning "Service is stoppable by non-System user!"
                            
                            # Manually set the variable so that PSScriptAnalyzer isn't confused by the scoping (I believe)
                            Set-Variable -Name "stopAceExists" -Value $true
                        }
                    }

                    # Set the external variable specifically based on the outcome of the ForEach loop
                    if ($stopAceExists -eq $true) {
                        $stoppableByNonSystemUsers = "yes"
                    }
                    else {
                        $stoppableByNonSystemUsers = "no"
                    }
                }
                else {
                    Write-Information "Security descriptor found, but no ACEs found"
        
                    # Assume that the service is *NOT* stoppable if the security ACL is present,
                    #   but there are no ACEs in the DACL that enable service stop
                    $stoppableByNonSystemUsers = "no"
                }
            }
            else {
                Write-Information "Invalid Security value: ${serviceSecurityRegPath}"

                # Assume that the service *IS* stoppable if a DACL has not been configured to prevent service stop
                $stoppableByNonSystemUsers = "yes"
            }
        }
        else {
            Write-Warning "Registry key not found: ${serviceSecurityRegPath}"

            # Assume that the service *IS* stoppable if a DACL has not been configured to prevent service stop
            $stoppableByNonSystemUsers = "yes"
        }

        return $stoppableByNonSystemUsers
    }
}

# Function that finds the DTD Uninstall registry key
function Get-DtdUninstallKey {
    [CmdletBinding()]
    [OutputType([string])]
    param (
    )

    begin {
        # Base portion of the Uninstall key path
        $uninstallKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    }

    process {
        # Enumerate through the Uninstall key until we've found the DTD uninstall key
        $dtdUninstallKeyPath = ""

        $uninstallKeys = Get-ChildItem -Path $uninstallKeyPath
        
        $uninstallKeys | ForEach-Object -Process {
            if ($_.Property -contains "DisplayName") {
                $displayName = Get-ItemPropertyValue $_.PsPath -Name "DisplayName"
        
                if ($displayName -eq "Dell Trusted Device") {
                    # Manually set the variable so that PSScriptAnalyzer isn't confused by the scoping (I believe)
                    Set-Variable -Name "dtdUninstallKeyPath" -Value $_.PsPath
                }
                if ($displayName -eq "Dell Trusted Device Agent") {
                    # Manually set the variable so that PSScriptAnalyzer isn't confused by the scoping (I believe)
                    Set-Variable -Name "dtdUninstallKeyPath" -Value $_.PsPath
                }
            }
        }

        return $dtdUninstallKeyPath
    }
}

# Retrieves the DTD product state & details
function Get-DtdProductInformation {
    [CmdletBinding()]
    [OutputType([DtdProductDetails])]
    param (
    )

    process {
        # Track a separate flag that indicates at a high level if the product appears to be installed
        $isInstalled = $false

        # Default installation directory
        $installDir = $null

        # Default product version
        $productVersion = $null

        # Retrieve the Uninstall key path and determine if the key exists
        $keyPath = Get-DtdUninstallKey

        if ($null -ne $keyPath -and "" -ne $keyPath) {
            if (Test-Path $keyPath) {
                # Acquire the installation path from the registry as an override for the default location
                $installDir = Get-ItemPropertyValue -Path $keyPath -Name "InstallLocation"
    
                # Acquire the numeric product version number
                $productVersionMajor = Get-ItemPropertyValue -Path $keyPath -Name "VersionMajor"
                $productVersionMinor = Get-ItemPropertyValue -Path $keyPath -Name "VersionMinor"
                $productVersionBuild = (Get-ItemPropertyValue -Path $keyPath -Name "Version") -band 0xffff
    
                $productVersion = "${productVersionMajor}.${productVersionMinor}.${productVersionBuild}"
    
                # Determine if the installation directory exists
                if (![string]::IsNullOrWhitespace($installDir)) {
                    # Only indicate that DTD is installed *IF* the path is valid and exists
                    if (Test-Path $installDir) {
                        $isInstalled = $true
                    }
                    else {
                        Write-Warning "Installation path does not exist: ${installDir}"
                    }
                }
                else {
                    Write-Warning "Installation path is null or empty"
                }
            }
            else {
                Write-Warning "Registry key not found: ${keyPath}"
            }
        }
        else {
            Write-Warning "Uninstall registry key could not be identified based on product DisplayName"
        }

        # Build the details object
        New-Object -TypeName DtdProductDetails -ArgumentList ($isInstalled, $installDir, $productVersion)
    }
}

# Retrieves the DTD service state & details
function Get-DtdServiceInformation {
    [CmdletBinding()]
    [OutputType([DtdServiceDetails])]
    param (
    )

    begin {
        # Build the registry key path and determine if the key exists
        $serviceKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\DellTrustedDevice"

        # The short name for the DTD service
        $serviceName = "DellTrustedDevice"
    }

    process {
        # Track a separate flag that indicates at a high level if the service appears to be installed
        $isInstalled = $false

        # Default values
        $version = $null
        $isSignedProperly = $false
        $isAutoStart = $false
        $isStoppable = "unknown"
        $isRunning = $false

        if (Test-Path $serviceKeyPath) {
            # Acquire the start type and determine if it has the expected value
            $startType = Get-ItemPropertyValue -Path $serviceKeyPath -Name "Start"
            if ($startType -eq 2) {
                $isAutoStart = $true
            }
            else {
                $isAutoStart = $false
            }

            # Find out if the service is running
            $service = Get-Service $serviceName
            if ($null -ne $service -and $service.Status -eq "Running") {
                $isRunning = $true
            }
            else {
                $isRunning = $false
            }

            # Retrieve the service's ACLs to determine if it is stoppable
            $isStoppable = Get-ServiceIsStoppable($serviceName)

            # Acquire additional properties from the executable file
            $imagePath = (Get-ItemPropertyValue -Path $serviceKeyPath -Name "ImagePath").Trim().Trim('"')

            # Determine if the image path exists
            if (![string]::IsNullOrWhitespace($imagePath)) {
                # Only retrieve file properties if the image path exists
                if (Test-Path -Path $imagePath -PathType Leaf) {
                    # Only flag it as installed if the binary exists
                    $isInstalled = $true

                    # Extract the FileVersion from the file properties
                    # FileVersion for our EXE has the format Major.Minor.Build.0
                    # ProductVersion for our EXE has the format YYMM.MajorVersion.MinorVersion
                    $version = Get-FileVersionWrapper($imagePath)

                    # Determine if the file is signed properly
                    $isSignedProperly = Get-DellSignatureValidity($imagePath)
                }
                else {
                    Write-Warning "Service binary not found: ${imagePath}"
                }
            }
            else {
                Write-Warning "Service path is null or empty"
            }
        }
        else {
            Write-Warning "Registry key not found: ${serviceKeyPath}"
        }

        # Build the details object
        New-Object -TypeName DtdServiceDetails -ArgumentList ($isAutoStart, $isStoppable, $isInstalled, $version, $isSignedProperly, $isRunning)
    }
}

# Retrieves the DTD SEL driver state & details
function Get-DtdSelDriverInformation {
    [CmdletBinding()]
    [OutputType([DtdSelDriverDetails])]
    param (
    )

    begin {
        # Registry path to the DTDSEL driver
        $driverKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\dtdsel"

        # Service name for the DTDSEL driver
        $serviceName = "dtdsel"
    }

    process {
        # Track a separate flag that indicates at a high level if the driver appears to be installed
        $isInstalled = $false

        # Default values
        $version = $null
        $isSignedProperly = $false
        $isSystemStart = $false
        $isRunning = $false

        # Determine if the driver key exists
        if (Test-Path $driverKeyPath) {
            # Acquire the start type and determine if it has the expected value
            $startType = Get-ItemPropertyValue -Path $driverKeyPath -Name "Start"
            if ($startType -eq 1) {
                $isSystemStart = $true
            }
            else {
                $isSystemStart = $false
            }

            # Find out if the service is running
            $service = Get-Service $serviceName
            if ($null -ne $service -and $service.Status -eq "Running") {
                $isRunning = $true
            }
            else {
                $isRunning = $false
            }

            # Acquire additional properties from the executable file
            # DTDSEL's ImagePath begins with system32, so we need to prepend the Windows directory path
            $imagePathSuffix = (Get-ItemPropertyValue -Path $driverKeyPath -Name "ImagePath").Trim().Trim('"')

            if (![string]::IsNullOrWhitespace($imagePathSuffix)) {
                # Only retrieve file properties if the image path exists
                $imagePath = Join-Path -Path $Env:WinDir -ChildPath $imagePathSuffix -Resolve

                # Determine if the image path exists
                if (Test-Path -Path $imagePath -PathType Leaf) {
                    # Only flag it as installed if the binary exists
                    $isInstalled = $true

                    # Extract the FileVersion from the file properties
                    # FileVersion for our EXE has the format Major.Minor.Build.0
                    # ProductVersion for our EXE has the format YYMM.MajorVersion.MinorVersion
                    $version = Get-FileVersionWrapper($imagePath)

                    # Determine if the file is signed properly
                    $isSignedProperly = Get-DellSignatureValidity($imagePath)
                }
                else {
                    Write-Warning "DTD SEL Driver binary not found: ${imagePath}"
                }
            }
            else {
                Write-Warning "DTD SEL Driver path is null or empty"
            }
        }
        else {
            Write-Warning "Registry key not found: ${driverKeyPath}"
        }

        # Build the details object
        New-Object -TypeName DtdSelDriverDetails -ArgumentList ($isSystemStart, $isInstalled, $version, $isSignedProperly, $isRunning)
    }
}

# Retrieves the DTD Bios Verification driver state & details
function Get-DellBvDriverInformation {
    [CmdletBinding()]
    [OutputType([DellBvDriverDetails])]
    param (
    )

    begin {
        # Registry path to the Dell BV driver
        $driverKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\dellbv"
    }

    process {
        # Track a separate flag that indicates at a high level if the driver appears to be installed
        $isInstalled = $false

        # Default values
        $version = $null
        $isSignedProperly = $false
        $isManualStart = $false
        $isRunning = $false

        # Determine if the driver registry key exists
        if (Test-Path $driverKeyPath) {
            # Acquire the start type and determine if it has the expected value
            $startType = Get-ItemPropertyValue -Path $driverKeyPath -Name "Start"
            if ($startType -eq 3) {
                $isManualStart = $true
            }
            else {
                $isManualStart = $false
            }

            # Acquire additional properties from the executable file
            # Dell BV's ImagePath begins with \systemroot, so we need to remove that and prepend the Windows directory path
            $imagePathSuffix = (Get-ItemPropertyValue -Path $driverKeyPath -Name "ImagePath").Trim().Trim('"') -replace "\SystemRoot"

            if (![string]::IsNullOrWhitespace($imagePathSuffix)) {
                # Only retrieve file properties if the image path exists
                $imagePath = Join-Path -Path $Env:WinDir -ChildPath $imagePathSuffix -Resolve

                # Determine if the image path exists
                if (Test-Path -Path $imagePath -PathType Leaf) {
                    # Only flag it as installed if the binary exists
                    $isInstalled = $true

                    # Extract the FileVersion from the file properties
                    # FileVersion for our EXE has the format Major.Minor.Build.0
                    # ProductVersion for our EXE has the format YYMM.MajorVersion.MinorVersion
                    $version = Get-FileVersionWrapper($imagePath)

                    # Determine if the file is signed properly
                    $isSignedProperly = Get-DellSignatureValidity($imagePath)
                }
                else {
                    Write-Warning "Dell BV Driver binary not found: ${imagePath}"
                }
            }
            else {
                Write-Warning "Dell BV Driver path is null or empty"
            }
        }
        else {
            Write-Warning "Registry key not found: ${driverKeyPath}"
        }

        # Build the details object
        New-Object -TypeName DellBvDriverDetails -ArgumentList ($isManualStart, $isInstalled, $version, $isSignedProperly, $isRunning)
    }
}

# Retrieves the Service Tag for the local machine
# This exists to facilitate unit tests through mocks
function Get-ServiceTag {
    [CmdletBinding()]
    [OutputType([string])]
    param (
    )

    begin {
    }

    process {
        # Retrieve the service tag via WMI
        $win32BiosInstance = Get-CimInstance -ClassName Win32_BIOS

        $svcTag = $win32BiosInstance.SerialNumber
        ##Write-Warning "Service Tag: ${svcTag}"

        # Return the retrieved service tag
        $svcTag
    }
}

# Retrieves the current system time in UTC
# This exists to facilitate unit tests through mocks
function Get-CurrentTimeInUtc {
    [CmdletBinding()]
    [OutputType([DateTime])]
    param (
    )

    begin {
    }

    process {
        # Retrieve the current time
        $currentTime = Get-Date

        # Return the current time in UTC
        $currentTime.ToUniversalTime()
    }
}

# Retrieves the domain for the DTD Cloud Service
# This exists to facilitate unit tests through mocks
function Get-DtdCloudServiceDomain {
    [CmdletBinding()]
    [OutputType([string])]
    param (
    )

    process {
        # Retrieve the cloud domain from somewhere...
        # Best suggestion so far is to hardcode this to the Production domain
        $cloudDomain = "signing.service.dtd.dell.com"

        $cloudDomain
    }
}

# Retrieves the URI for the DTD Cloud Service
# This exists to facilitate unit tests through mocks
function Get-DtdCloudServiceUri {
    [CmdletBinding()]
    [OutputType([string])]
    param (
    )

    process {
        # Retrieve the cloud URI from somewhere...
        # Best suggestion so far is to hardcode this to the Production URI
        $cloudUri = "https://signing.service.dtd.dell.com/"

        $cloudUri
    }
}

# Extracts ASN formatted entries from a X500 Distinguished Name string
function Get-ASNFormattedValue {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$distNameString,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        [string]$oid
    )

    process {
        # Build a distinguished name object from the provided string
        $distName = New-Object -TypeName System.Security.Cryptography.X509Certificates.X500DistinguishedName -ArgumentList ($distNameString)

        # Create an ASN encoded data value for the provided OID
        $asnValueData = New-Object -TypeName System.Security.Cryptography.AsnEncodedData -ArgumentList ($oid, $distName.RawData)

        # Format the value
        $asnValue = $asnValueData.Format($false)

        # And return the formatted value
        $asnValue
    }
}

# Extracts the Subject Key Identifier string from an instance of a Subject Key Identifier Extension
# This exists to facilitate unit tests through mocks
function Get-SkiFromExtension {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
            [System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]$skiExt
    )

    process {
        # And return the SKI string
        $skiExt.SubjectKeyIdentifier
    }
}

# Extracts the SubjectKeyIdentifier from the provided certificate's extensions
function Get-SubjectKeyIdentifier {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
            [System.Security.Cryptography.X509Certificates.X509Certificate2]$cert
    )

    process {
        $subjectKeyIdentifier = ""

        # Find the Subject Key identifier extension
        $cert.Extensions | ForEach-Object -Process {
            if ($_.Oid.FriendlyName -eq "Subject Key Identifier") {
                $skiString = Get-SkiFromExtension -skiExt $_
                Set-Variable -Name "subjectKeyIdentifier" -Value $skiString
            }
        }

        # Ensure the subject key identifier is valid
        if ([string]::IsNullOrWhiteSpace($subjectKeyIdentifier)) {
            Write-Warning "Subject Key Identifier could not be found."
        }

        # And return the formatted value
        $subjectKeyIdentifier
    }
}

# Extracts the Authority Key Identifier string from the content of an Authority Key Identifier Extension
# This exists to facilitate unit tests through mocks
function Get-AkiFromExtension {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
            [System.Security.Cryptography.X509Certificates.X509Extension]$akiExt
    )

    process {
        # Get the formatted content of the extension
        $akiData = $akiExt.Format($false)
        ##Write-Warning "Authority Key Identifier Data: ${akiData}"

        # Split the value apart on the equals sign
        $akiComponents = $akiData -Split "="

        # Convert the AKI to uppercase
        $akiString = $akiComponents[1].ToUpper()
        ##Write-Warning "Authority Key Identifier: ${akiString}"

        # And return the AKI string
        $akiString
    }
}

# Extracts the AuthorityKeyIdentifier from the provided certificate's extensions
function Get-AuthorityKeyIdentifier {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
            [System.Security.Cryptography.X509Certificates.X509Certificate2]$cert
    )

    process {
        $authorityKeyIdentifier = ""

        # Find the Subject Key identifier extension
        $cert.Extensions | ForEach-Object -Process {
            if ($_.Oid.FriendlyName -eq "Authority Key Identifier") {
                $akiString = Get-AkiFromExtension -akiExt $_

                Set-Variable -Name "authorityKeyIdentifier" -Value $akiString
            }
        }

        # Ensure the authority key identifier is valid
        if ([string]::IsNullOrWhiteSpace($authorityKeyIdentifier)) {
            Write-Warning "Authority Key Identifier could not be found."
        }

        # And return the formatted value
        $authorityKeyIdentifier
    }
}

# Extracts the trusted domain content from the Subject Alternative Name Extension
# This exists to facilitate unit tests through mocks
function Get-TrustedDomainsFromExtension {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
            [System.Security.Cryptography.X509Certificates.X509Extension]$sanExt
    )

    process {
        # Get the formatted content of the extension
        $sanData = $sanExt.Format($false)
        ##Write-Warning "Subject Alternative Name Data: ${sanData}"

        # Split the string to get the list of domain name entries
        $sanEntryList = $sanData -Split ", "

        # For each entry in the list, split on the equals sign to get only the domain name
        $trustedDomains = @()

        $sanEntryList | ForEach-Object -Process {
            # Split the entry value, which has the format: DNS Name=bas.solution.delltrusteddevicesecurity.com
            $entryComponents = $_ -Split "="

            # Convert to lower-case for ease of comparison later
            $trustedDomain = $entryComponents[1].ToLower()

            # Add this domain to the array
            $trustedDomains += $trustedDomain
        }

        # And return the list of trusted domains
        $trustedDomains
    }
}

# Extracts the trusted domains from the Subject Alternative Name in the provided certificate's extensions
function Get-CertificateTrustedDomainList {
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
            [System.Security.Cryptography.X509Certificates.X509Certificate2]$cert
    )

    process {
        $trustedDomains = @()

        # Find the Subject Alternative Name extension
        $cert.Extensions | ForEach-Object -Process {
            if ($_.Oid.FriendlyName -eq "Subject Alternative Name") {
                $extTrustedDomains = Get-TrustedDomainsFromExtension -sanExt $_
                ##Write-Warning "SAN Trusted Domains: ${extTrustedDomains}"

                Set-Variable -Name "trustedDomains" -Value $extTrustedDomains
            }
        }

        # Ensure that there is at least one trusted domain
        if ($trustedDomains.Count -eq 0) {
            Write-Warning "Certificate did not contain any trusted domains"
        }

        # And return the list of trusted domains
        $trustedDomains
    }
}

# Dump certificate properties
function Show-Certificate {
    [CmdletBinding()]
    [OutputType([System.Void])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$identifier,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$cert
    )

    process {
        # Dump some cert properties
        $subject = $cert.Subject
        Write-Warning "${identifier} Cert Subject: ${subject}"

        $hashSha1 = $cert.GetCertHashString("SHA1")
        Write-Warning "${identifier} Cert Hash (SHA1): ${hashSha1}"

        $hashSha256 = $cert.GetCertHashString("SHA256")
        Write-Warning "${identifier} Cert Hash (SHA256): ${hashSha256}"

        $san = $cert.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::DnsName, $false)
        Write-Warning "${identifier} Cert SAN: ${san}"

        $commonName = Get-ASNFormattedValue -distNameString $subject -oid "CN"
        Write-Warning "${identifier} Cert Common Name: ${commonName}"

        $notBefore = $cert.NotBefore
        Write-Warning "${identifier} Cert Not Before: ${notBefore}"

        $notAfter = $cert.NotAfter
        Write-Warning "${identifier} Cert Not After: ${notAfter}"

        $ski = Get-SubjectKeyIdentifier -cert $cert
        Write-Warning "${identifier} Cert Subject Key Identifier: ${ski}"

        $aki = Get-AuthorityKeyIdentifier -cert $cert
        Write-Warning "${identifier} Cert Authority Key Identifier: ${aki}"
    }
}

# Decode a Base64-encoded certificate
function Get-DecodedCert {
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$base64EncodedCert
    )

    process {
        # Decode the cert into a byte array
        $certAsBytes = [System.Convert]::FromBase64String($base64EncodedCert)

        # Create a cert from the decoded bytes
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(, $certAsBytes)

        # And return the cert
        $cert
    }
}

# Asks the certificate to verify itself
# This exists to facilitate unit tests through mocks
function Test-CertificateValidity {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
            [System.Security.Cryptography.X509Certificates.X509Certificate2]$cert
    )

    process {
        # Call the certificate's Verify method and return the result
        $cert.Verify()
    }
}

# Builds the certificate chain
# This exists to facilitate unit tests through mocks
function Get-CertificateChain {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
            [System.Security.Cryptography.X509Certificates.X509Chain]$chain,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
            [System.Security.Cryptography.X509Certificates.X509Certificate2]$cert
    )

    process {
        # Call the certificate chain's Build method and return the result
        $chain.Build($cert)
    }
}

# Gets the root certificate from the chain
# This exists to facilitate unit tests through mocks
function Get-RootCertificateFromChain {
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
            [System.Security.Cryptography.X509Certificates.X509Chain]$chain
    )

    process {
        $rootCert = $null

        # Ensure that there is at least one entry in the chain
        if ($chain.ChainElements.Count -gt 0) {
            $rootCert = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate
        }

        # And return the discovered certificate
        $rootCert
    }
}

# Determines if the SSL certificate for the DTD Cloud Service has properties that indicate that it is trusted
# Exceptions are thrown if any properties do not meet trust / validity requirements.
function Test-DtdCloudServiceCertificate {
    [CmdletBinding()]
    [OutputType([System.Void])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$cloudCert
    )

    begin {
        # Trusted root cert thumbprint
        $trustedRootThumbprints = @(
            # CN=ISRG Root X1, O=Internet Security Research Group, C=US
            "96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6",

            # CN=Entrust Root Certification Authority - G2, OU="(c) 2009 Entrust, Inc. - for authorized use only", OU=See www.entrust.net/legal-terms, O="Entrust, Inc.", C=US
            "43DF5774B03E7FEF5FE40D931A7BEDF1BB2E6B42738C4E6D3841103D3AA7F339",

            # CN=DST Root CA X3, O=Digital Signature Trust Co.
            "0687260331A72403D909F105E69BCF0D32E1BD2493FFC6D9206D11BCD6770739",

            # CN=DigiCert Global Root G2, OU=www.digicert.com, O=DigiCert Inc, C=US
            "CB3CCBB76031E5E0138F8DD39A23F9DE47FFC35E43C1144CEA27D46A5AB1CB5F",

            # CN=DigiCert Global Root G3, OU=www.digicert.com, O=DigiCert Inc, C=US
            "31AD6648F8104138C738F39EA4320133393E3A18CC02296EF97C2AC9EF6731D0"
        )

        # Trusted domain
        $trustedDomain = Get-DtdCloudServiceDomain
    }

    process {
        ##Show-Certificate -identifier "SSL Cert" -cert $cloudCert

        # Verify the cert
        $certPassedVerification = Test-CertificateValidity -cert $cloudCert
        if ($true -ne $certPassedVerification) {
            throw "DTD Cloud Service SSL certificate failed verification."
        }

        # Create an X.509 Certificate Chain object
        $x509Chain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain
        if ($null -eq $x509Chain) {
            throw "Failed to build certificate chain for DTD Cloud Service SSL certificate."
        }

        # Build the certificate chain
        $chainIsValid = Get-CertificateChain -chain $x509Chain -cert $cloudCert
        if ($true -ne $chainIsValid) {
            throw "Certificate chain for DTD Cloud Service SSL certificate was invalid."
        }

        # Acquire the last certificate in the chain, which should be the root certificate
        $rootCert = Get-RootCertificateFromChain -chain $x509Chain
        if ($null -eq $rootCert) {
            throw "Root certificate for DTD Cloud Service SSL certificate was invalid."
        }

        ##Show-Certificate -identifier "SSL Root Cert" -cert $rootCert

        # Get the cert thumbprint
        $rootCertThumbprint = Get-ThumbprintFromCert -certificate $rootCert
        ##Write-Warning "Cloud Cert Root Cert Thumbprint: ${rootCertThumbprint}"

        if ($true -ne $trustedRootThumbprints.Contains($rootCertThumbprint)) {
            throw "DTD Cloud Service SSL certificate's root certificate is not trusted."
        }

        # Retrieve the current time
        $currentTime = Get-Date

        $validFrom = $cloudCert.NotBefore
        ##Write-Warning "Cloud Cert Not Before: ${validFrom}"

        $validUntil = $cloudCert.NotAfter
        ##Write-Warning "Cloud Cert Not After: ${validUntil}"

        if ($currentTime -lt $validFrom) {
            throw "DTD Cloud Service SSL certificate is not valid until ${validFrom}"
        }
        if ($currentTime -gt $validUntil) {
            throw "DTD Cloud Service SSL certificate expired on ${validUntil}"
        }

        # Get the certificate's trusted domains
        $certTrustedDomains = Get-CertificateTrustedDomainList -cert $cloudCert
        ##Write-Warning "Cloud Cert Trusted Domains: ${certTrustedDomains}"

        # Ensure that the certificate's trusted domains list contains our trusted domain value
        if (!$certTrustedDomains.Contains($trustedDomain)) {
            throw "DTD Cloud Service SSL certificate does not contain trusted domain."
        }
    }
}

# Retrieves the SSL certificate for a URI
# This exists to facilitate unit tests through mocks
function Get-SslCertFromServicePoint {
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$uri
    )

    process {
        $servicePoint = [System.Net.ServicePointManager]::FindServicePoint($uri)

        $servicePoint.Certificate
    }
}

# Retrieves the plugin signing certificate chain from the DTD Cloud Service
function Get-PluginSigningCertChain {
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$cert,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
            [string]$version
    )

    process {
        $certList = $null

        # Acquire the certificate hash from the certificate
        $certHash = $cert.GetCertHash("SHA256")
        ##Write-Warning "Cert Hash: ${certHash}"

        # Base64 encode the certificate hash
        $certHashBase64 = [System.Convert]::ToBase64String($certHash)
        ##Write-Warning "Cert Hash (Base64): ${certHashBase64}"

        # URL-encode the cert hash
        $certHashUrlEncoded = $certHashBase64 -replace "\+", "-" -replace "/", "_" -replace "=", ""
        ##Write-Warning "Cert Hash URL Encoded '${certHashUrlEncoded}'"

        # Prepare the traceabilty header values
        $traceabiltyHeader = @{
            "ClientAppVersion" = "${version}"
            "ClientAppName" = "MEM"
        }

        # Retrieve the API URI
        $cloudUri = Get-DtdCloudServiceUri

        # Build the request Uri string
		$requestUri = "${cloudUri}signing/api/v1/certchain?kid=${certHashUrlEncoded}"
        ##Write-Warning "Request URI String: ${requestUri}"

        # Request the cert chain from the DTD Cloud Service
        $webResp = Invoke-WebRequest -Uri $requestUri -Headers $traceabiltyHeader -TimeoutSec 5 -UseBasicParsing -Method GET

        if ($null -ne $webResp) {
            # Acquire the SSL cert and validate it
            $sslCert = Get-SslCertFromServicePoint -uri $cloudUri

            ##Show-Certificate -identifier "DTD Cloud Service SSL" -cert $sslCert

            # Determine if the SSL certificate is trusted
            Test-DtdCloudServiceCertificate -cloudCert $sslCert

            # Convert the output into a list
            $certList = $webResp.content | ConvertFrom-Json
            ##Write-Warning "Cert List: ${certList}"
        }
        else {
            Write-Warning "Unable to retrieve signing certificate chain for certificate with hash ${certHash}"
        }

        ##Write-Warning "CertList: ${certList}"

        # Return the certificate chain
        $certList
    }
}

# Performs an RSA signature validation of the provided data
# This exists to facilitate unit tests through mocks
function Test-RsaDataSignature {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [System.Security.Cryptography.RSA]$rsaPublicKey,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        [byte[]]$dataBytes,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 2)]
        [byte[]]$signatureBytes,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 3)]
        [System.Security.Cryptography.HashAlgorithmName]$algorithmName
    )

    process {
        $rsaPublicKey.VerifyData($dataBytes, $signatureBytes, $algorithmName, [System.Security.Cryptography.RSASignaturePadding]::Pss)
    }
}

# Verifies the json payload signature
function Test-PayloadSignature {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
            [object]$jsonObj,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
            [string]$jsonPayload,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
            [System.Security.Cryptography.X509Certificates.X509Certificate2]$signingCert
    )

    process {
        $result = $false

        # Get the bytes for this content
        $jsonPayloadBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)

        # Decode the signature
        $signatureBytes = [System.Convert]::FromBase64String($jsonObj.signature.value)

        # Acquire the algorithm name
        if ($null -eq $jsonObj.signature.alg) {
            $algorithmString = $jsonObj.signature.hashAlg
        }
        else {
            $algorithmString = $jsonObj.signature.alg
        }

        if ("sha256" -eq $algorithmString) {
            $algorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA256
        } 
        elseif ("sha384" -eq $algorithmString) {
            $algorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA384
        }
        elseif ("sha512" -eq $algorithmString) {
            $algorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA512
        }

        # Verify the signature
        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($signingCert)

        try {
            $result = Test-RsaDataSignature -rsaPublicKey $rsa -dataBytes $jsonPayloadBytes -signatureBytes $signatureBytes -algorithmName $algorithm
        }
        catch {
            Write-Warning "${_}"
        }

        if ($true -ne $result) {
            Write-Warning "Payload signature validation failed"
        }

        # Return the signature validation result
        $result
    }
}

# Extracts the service tag from the JSON payload object
function Get-PayloadServiceTag {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [object]$jsonObj
    )

    begin {
    }

    process {
        $svcTag = ""

        $endpointIds = $jsonObj.payload.endpointIds
        ##Write-Warning "Endpoint IDs: ${endpointIds}"

        # Find the service tag entry inside the endpoint IDs array
        $endpointIds | ForEach-Object -Process {
            if ($_.idType -eq "serviceTag") {
                # Manually set the variable so that PSScriptAnalyzer isn't confused by the scoping (I believe)
                Set-Variable -Name "svcTag" -Value $_.value
            }
        }

        if ([string]::IsNullOrWhiteSpace($svcTag)) {
            Write-Warning "BIOS Verification results did not contain the service tag"
        }

        # Return the service tag, if it was found
        $svcTag
    }
}

# Verifies that the certificate chain for the signing certificate is valid
# Exceptions are thrown if any properties do not meet trust / validity requirements.
function Test-SigningCertificateChain {
    [CmdletBinding()]
    [OutputType([System.Void])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string[]]$certChain
    )

    begin {
    }

    process {
        # Ensure that there is a valid certificate chain
        if ($certChain.Count -lt 2) {
            throw "Certificate chain for the certificate in the BIOS Verification result does not have enough entries."
        }

        ##Write-Warning "CertChain: ${certChain}"

        # Verify that each certificate's authority key identifier matches its parent certificate's subject key identifier
        # Do not verify the last element in the chain, since it is the root (hence count - 1)
        for ($currCertIdx = 0; $currCertIdx -lt $certChain.Count - 1; $currCertIdx++) {
            # Decode the child certificate
            $childCertString = $certChain[$currCertIdx]
            try {
                $childCert = Get-DecodedCert -base64EncodedCert $childCertString
                ##Show-Certificate -identifier "Child Cert" -cert $childCert
            }
            catch {
                throw "Current certificate failed to decode."
            }

            # Acquire the child certificate's AKI
            $aki = Get-AuthorityKeyIdentifier -cert $childCert
            ##Write-Warning "Child Cert AKI: ${aki}"

            if ([string]::IsNullOrWhiteSpace($aki)) {
                throw "Current certificate's Authority Key Identifier is invalid."
            }

            # Decode the parent certificate
            $parentCertString = $certChain[$currCertIdx + 1]
            try {
                $parentCert = Get-DecodedCert -base64EncodedCert $parentCertString
                ##Show-Certificate -identifier "Parent Cert" -cert $parentCert
            }
            catch {
                throw "Parent certificate failed to decode."
            }

            # Acquire the parent certificate's SKI
            $ski = Get-SubjectKeyIdentifier -cert $parentCert
            ##Write-Warning "Parent Cert SKI: ${ski}"

            if ([string]::IsNullOrWhiteSpace($ski)) {
                throw "Parent certificate's Subject Key Identifier is invalid."
            }

            # Compare the AKI and SKI to ensure that they match
            if ($aki -ne $ski) {
                throw "Current certificate's Authority Key Identifier does not match its parent certificate's Subject Key Identifier."
            }
        }
    }
}

# Retrieves the DTD installation directory based on the service image path
function Get-InstallDirFromServiceRegistryEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param (
    )

    begin {
        # Build the registry key path and determine if the key exists
        $serviceKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\DellTrustedDevice"
    }

    process {
        $installDir = ""

        # Verify that the service registry entry exists
        if (Test-Path $serviceKeyPath) {
            # Acquire the image path
            $imagePath = (Get-ItemPropertyValue -Path $serviceKeyPath -Name "ImagePath").Trim().Trim('"')
    
            # Determine if the image path exists
            if (![string]::IsNullOrWhitespace($imagePath)) {
                # Only retrieve the installation directory if the image path exists
                if (Test-Path -Path $imagePath -PathType Leaf) {
                    # Remove the last path component
                    $installDir = Split-Path $imagePath
                    ##Write-Warning "Installation Directory: ${installDir}"
                }
                else {
                    Write-Warning "Dell Trusted Device service binary was not found: ${imagePath}"
                }
            }
            else {
                Write-Warning "Dell Trusted Device service path is null or empty"
            }
        }
        else {
            Write-Warning "Dell Trusted Device service registry key was not found: ${serviceKeyPath}"
        }

        if ([string]::IsNullOrWhiteSpace($installDir)) {
            Write-Warning "Unable to identify Dell Trusted Device installation directory"
        }

        # Return the installation directory
        $installDir
    }
}

# Loads a DTD assembly after verifying the signature
#
# IMPORTANT NOTE:
#   Once a Type is loaded from an assembly, the assembly remains loaded
#       for the remainder of the PowerShell session.
#   Therefore, these assemblies will be locked on disk and cannot be replaced,
#       such as during a product upgrade, until the PowerShell session is closed.
#
function Import-DtdAssembly {
    [CmdletBinding()]
    [OutputType([System.Void])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$assemblyPath
    )

    begin {
    }

    process {
        $loadedAssembly = $null

        # Verify the signature for the assembly DLL
        $signatureIsValid = Get-DellSignatureValidity -binaryPath $assemblyPath
        if ($signatureIsValid) {
            # Load the assembly
            try {
                $loadedAssembly = Add-Type -Path $assemblyPath -PassThru
            }
            catch {
                Write-Warning $_
            }
        }

        if ($null -eq $loadedAssembly) {
            throw "Unable to load Dell Trusted Device assembly: ${assemblyPath}"
        }
    }
}

# Retrieves the result JSON string for the target GUID via IPC to the Dell Trusted Device service
function Get-PluginResultsFromIPC {
    [CmdletBinding()]
    [OutputType([DtdPluginIpcResultInfo])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [GUID]$pluginGuid
    )

    begin {
        # Maximum number of times to ask the IPC server if the primary action has completed
        $ipcGetStatusMaxCount = 10

        # Number of seconds to sleep in between IPC server requests
        $ipcSleepInSeconds = 1
    }

    process {
        [DtdPluginIpcResultInfo]$resultObj = $null
        $pluginResultContent = ""
        $errorCode = 0  # Default to success, since this value will not be present for Registry or File results
		
        # Acquire the DTD install dir
        $installDir = Get-InstallDirFromServiceRegistryEntry
        if (![string]::IsNullOrWhiteSpace($installDir)) {
            # Load the DCF Common assembly
            $dcfCommonDllPath = Join-Path -Path $installDir -ChildPath "DCF.Common.dll"
            Import-DtdAssembly -assemblyPath $dcfCommonDllPath

            # Instantiate a new log file
            $logFile = New-Object -TypeName Dell.Client.Framework.Common.LogFile -ArgumentList ("MEM-PowerShell", "TrustedDevice")
            $log = New-Object -TypeName Dell.Client.Framework.Common.Log -ArgumentList ("IPC", $logFile, [string]::empty)

            # Load the DTD Common assembly
            $dtdCommonDllPath = Join-Path -Path $installDir -ChildPath "Dell.TrustedDevice.Common.dll"
            Import-DtdAssembly -assemblyPath $dtdCommonDllPath

            # Instantiate a log helper
            $logHelper = New-Object -TypeName Dell.TrustedDevice.Common.LogHelper -ArgumentList $log

            # Load the IPC callback assembly
            $ipcCallbackDllPath = Join-Path -Path $installDir -ChildPath "Dell.TrustedDevice.IPC.Callback.dll"
            Import-DtdAssembly -assemblyPath $ipcCallbackDllPath

            # Load the LocalConsole common assembly
            $localConsoleCommonDllPath = Join-Path -Path $installDir -ChildPath "Dell.TrustedDevice.DeveloperConsole.Common.dll"
            Import-DtdAssembly -assemblyPath $localConsoleCommonDllPath

            # Instantiate the IPC client
            $ipcClient = Invoke-Method -targetObject ([Dell.TrustedDevice.LocalConsole.Common.IpcServiceClientCommon]) -isStaticMethod $true -methodName "GetServiceClientInstance" -arguments @( $logHelper )
            if ($null -ne $ipcClient) {
                # Loop until the IPC indicates that the request completed, or a timeout or error occurred
                for ($ctr = 0; $ctr -lt $ipcGetStatusMaxCount; $ctr++) {
                    # Check the status
                    $statusResult = Invoke-Method -targetObject $ipcClient -isStaticMethod $false -methodName "GetLastStatus" -arguments @( $pluginGuid )
                    if ($null -ne $statusResult) {
                        $msgType = $statusResult.MessageType

                        # If the IPC indicates the request has completed, save the result and stop checking
                        if ($msgType -eq "Completed") {
                            # Extract the server response data from the content
                            $jsonData = $statusResult.JsonData
                            ##Write-Warning "Plugin $pluginGuid IPC JSON data: $jsonData"
                            $ipcResultObj = ConvertFrom-Json $jsonData
							if ($null -eq $ipcResultObj.ScvDataInfo) {							
								$pluginResultContent = $ipcResultObj.ServerResponseData | ConvertTo-Json -Compress -Depth 100
								if ($null -eq $ipcResultObj.ReturnCode) {
										$errorCode = $ipcResultObj.VerificationResultCode	# ME Verification server result
								}
								else {
										$errorCode = $ipcResultObj.ReturnCode				# BIOS Verification server result
								}
							}
							else {
								$pluginResultContent = $ipcResultObj.ScvDataInfo.ScvMeasurementsResponse | ConvertTo-Json -Compress -Depth 100
								# Default this value until the service returns something useful
								$errorCode = 0											# Secured Component Verification server result
							}

                            # Return the file contents, if any, along with the error code
                            $resultObj = New-Object -TypeName DtdPluginIpcResultInfo -ArgumentList ($pluginResultContent, $errorCode)

                            # Break out to avoid further IPC requests
                            break
                        }
                        elseif ($msgType -eq "Error") {
                            # If there was an error, log the result and stop checking.
                            $msg = $statusResult.Message

                            Write-Warning "DTD Service indicated that Plugin Verification processing failed: ${msg}"

                            # Break out to avoid further IPC requests
                            break
                        }
                        else {
                            # Otherwise, simply report the message
                            $msg = $statusResult.Message

                            Write-Warning "DTD Service responded with Plugin Verification status: ${msg}"
                        }
                    }
                    else {
                        Write-Warning "DTD Service did not respond with Plugin Verification status"

                        # Break out to avoid further IPC requests
                        break
                    }

                    # Sleep for some time in between requests
                    Start-Sleep -Seconds $ipcSleepInSeconds
                }

                # Dispose of the IPC client
                Invoke-Method -targetObject $ipcClient -isStaticMethod $false -methodName "Dispose"
                $ipcClient = $null
            }
            else {
                Write-Warning "Failed to create Dell Trusted Device IPC Client for Plugin"
            }

            # Dispose of the log objects
            if ($null -ne $logHelper) {
                $logHelper = $null
            }
            if ($null -ne $log) {
                $log = $null
            }
            if ($null -ne $logFile) {
                Invoke-Method -targetObject $logFile -isStaticMethod $false -methodName "Dispose"
                $logFile = $null
            }
        }

        if ($null -eq $resultObj) {
            Write-Warning "Failed to retrieve Plugin Verification result via IPC"
        }

        # Return the result
        $resultObj
    }
}

# Retrieves the BV Result JSON string from the Registry
function Get-BVResultsFromRegistry {
    [CmdletBinding()]
    [OutputType([string])]
    param (
    )

    begin {
        # Path to the BV Results key
        $bvResultsRegistryKeyPath = "HKLM:\SOFTWARE\Dell\BiosVerification"
    }

    process {
        $bvResultContent = ""

        # Verify that the provided path exists
        if (Test-Path $bvResultsRegistryKeyPath) {
            # Get the registry value data
            $bvResultContent = Get-ItemPropertyValue -Path $bvResultsRegistryKeyPath -Name "Result.json"

            ##Write-Warning "BIOS Verification result: ${bvResultContent}"
        }
        else {
            Write-Warning "BIOS Verification result registry key was not found: ${bvResultsRegistryKeyPath}"
        }
    
        if ([string]::IsNullOrWhiteSpace($bvResultContent)) {
            Write-Warning "BIOS Verification result was not found in the Registry"
        }

        # Return the file contents, if any
        $bvResultContent
    }
}

# Retrieves the Plugin Result JSON string from the Registry
function Get-PluginResultsFromRegistry {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$pluginGuid
    )

    begin {
        # Path to the Plugin Results key
        $pluginResultsRegistryKeyPath = "HKLM:\SOFTWARE\Dell\TrustedDevice\Results"
    }

    process {
        $pluginResultContent = ""

        # Verify that the provided path exists
        if (Test-Path $pluginResultsRegistryKeyPath) {
            # Get the registry value data
            $pluginResultContent = Get-ItemPropertyValue -Path $pluginResultsRegistryKeyPath -Name "$($pluginGuid).json"

            ##Write-Warning "Plugin ${pluginGuid} Verification result: ${pluginResultContent}"
        }
        else {
            Write-Warning "BIOS Verification result registry key was not found: ${pluginResultsRegistryKeyPath}"
        }
    
        if ([string]::IsNullOrWhiteSpace($pluginResultContent)) {
            Write-Warning "Plugin ${pluginGuid} Verification result was not found in the Registry"
        }

        # Return the file contents, if any
        $pluginResultContent
    }
}

# Retrieves the BV Result JSON string from the file on disk
function Get-BVResultsFromFile {
    [CmdletBinding()]
    [OutputType([string])]
    param (
    )

    begin {
        # Path to the BV Results file
        $bvResultsFilePath = "C:\ProgramData\Dell\BiosVerification\Result.json"
    }

    process {
        $fileContents = ""

        # Verify that the provided path exists
        if (Test-Path $bvResultsFilePath) {
            # Get the size of the file and ensure that it is greater than zero bytes in length
            $file = Get-Item -Path $bvResultsFilePath
            if ($file.Length -gt 0) {
                $fileContents = Get-Content -Path $bvResultsFilePath
            }
            else {
                Write-Warning "BIOS Verification result file is empty: ${bvResultsFilePath}"
            }
        }
        else {
            Write-Warning "BIOS Verification result file was not found: ${bvResultsFilePath}"
        }
    
        # Return the file contents, if any
        $fileContents
    }
}

# Retrieves the Plugin Result JSON string from the file on disk
function Get-PluginResultsFromFile {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$pluginGuid
    )

    begin {
        # Path to the Plugin Results file
        # $textPluginGuid = @($pluginGuid)
        $pluginResultsFilePath = "C:\ProgramData\Dell\TrustedDevice\Results\$($pluginGuid).json"
    }

    process {
        $fileContents = ""

        # Verify that the provided path exists
        if (Test-Path $pluginResultsFilePath) {
            # Get the size of the file and ensure that it is greater than zero bytes in length
            $file = Get-Item -Path $pluginResultsFilePath
            if ($file.Length -gt 0) {
                $fileLines = Get-Content -Path $pluginResultsFilePath
                $fileContents = [string] $fileLines
            }
            else {
                Write-Warning "Plugin Verification result file is empty: ${pluginResultsFilePath}"
            }
        }
        else {
            Write-Warning "Plugin Verification result file was not found: ${pluginResultsFilePath}"
        }
    
        # Return the file contents, if any
        $fileContents
    }
}

# Acquires the BV result details
function Get-DellBvResult {
    [CmdletBinding()]
    [OutputType([DtdBvResultDetails])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$version
    )

    begin {
    }

    process {
        # Default values
        $bvResultContent = ""
        $isAvailable = $false
        $sourceIsValid = $false
        $resultSourceName = "unknown"
        $indicatesSuccess = $false
        $errorCode = 0    # Default to success, since this value will not be present for Registry or File results
        $resultAgeInDays = 0
        $tamperingDetected = $false
        $biosIsInvalid = $false
        $biosNotSupported = $false
        $clientErrorOccurred = $false
        $serverErrorOccurred = $false

        # Retrieve the BV result string via the IPC, if possible
        try {
            $bvIpcResult = Get-PluginResultsFromIPC([GUID]"4345CBAD-0910-48C1-B822-901A809A5590")
        }
        catch {
            Write-Warning "Exception occurred during request for BIOS Verification from the Dell Trusted Device service: ${_}"
        }
        
        if ($null -ne $bvIpcResult) {
            # Save the result source if the processing succeeded
            $resultSourceName = "service"

            # Save the content and error code returned
            $bvResultContent = $bvIpcResult.ResultJson
            $errorCode = $bvIpcResult.ErrorCode

            # Interpret the error code values
            if ($errorCode -ne 0) {
                if ($errorCode -eq 1) {
                    Write-Warning "Dell Trusted Device service indicated that the BIOS is invalid during BIOS Verification."
                    $biosIsInvalid = $true
                }
                elseif ($errorCode -eq 2) {
                    Write-Warning "Dell Trusted Device service indicated that tampering was detected during BIOS Verification."
                    $tamperingDetected = $true
                }
                elseif ($errorCode -eq 11) {
                    Write-Warning "Dell Trusted Device service indicated that the BIOS is not supported during BIOS Verification."
                    $biosNotSupported = $true
                }
                elseif ($errorCode -eq 7 -or $errorCode -eq 13) {
                    Write-Warning "Dell Trusted Device service indicated that a server error occurred during BIOS Verification."
                    $serverErrorOccurred = $true
                }
                else {
                    # Otherwise, this is a client error
                    Write-Warning "Dell Trusted Device service indicated that a client error occurred during BIOS Verification."
                    $clientErrorOccurred = $true
                }
            }
        }
        else {
            # If the IPC failed, try the Registry
            Write-Warning "Falling back to Registry for BIOS Verification result"

            try {
                try {
                    $registryContent = Get-PluginResultsFromRegistry("4345CBAD-0910-48C1-B822-901A809A5590")
                }
                catch {
                    Write-Warning "Exception occurred during retrieval of BIOS Verification from the Registry: ${_}"
                }
 
                if ([string]::IsNullOrWhiteSpace($registryContent)) {
                    $registryContent = Get-BVResultsFromRegistry
                }
            }
            catch {
                Write-Warning "Exception occurred during retrieval of legacy BIOS Verification from the Registry: ${_}"
            }

            if (![string]::IsNullOrWhiteSpace($registryContent)) {
                $resultSourceName = "registry"
                $bvResultContent = $registryContent
            }
            else {
                # If the Registry failed validation, check the filesystem
                Write-Warning "Falling back to filesystem for BIOS Verification result"

                try {
                    try {
                        $fileSystemContent = Get-PluginResultsFromFile("4345CBAD-0910-48C1-B822-901A809A5590")
                    }
                    catch {
                        Write-Warning "Exception occurred during retrieval of BIOS Verification from the filesystem: ${_}"
                    }

                    if ([string]::IsNullOrWhiteSpace($fileSystemContent)) {
                        $fileSystemContent = Get-BVResultsFromFile
                    }
                }
                catch {
                    Write-Warning "Exception occurred during retrieval of legacy BIOS Verification from the filesystem: ${_}"
                }

                if (![string]::IsNullOrWhiteSpace($fileSystemContent)) {
                    $resultSourceName = "filesystem"
                    $bvResultContent = $fileSystemContent
                }
				else {
					$errorCode = 11    # Platform not supported
					$biosNotSupported = $true
				}
            }
        }

        ##Write-Warning "BV Result: ${bvResultContent}"
        
        # Ensure that we received some kind of content
        if (![string]::IsNullOrWhiteSpace($bvResultContent)) {
            # Catch all exceptions that occur while processing the BV Result content
            try {
                # Turn the JSON string into an object
                try {
                    $jsonObj = ConvertFrom-Json $bvResultContent
                }
                catch {
                    throw "Failed to parse BIOS Verification result: ${_}"
                }

                # Ensure that a payload is present in the JSON object
                if ($null -ne $jsonObj.payload) {
                    if ($jsonObj.payload -is [string]) {
					    $payloadText = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($jsonObj.payload))
					    $payload = ConvertFrom-Json $payloadText
                    }
                    else {
                        $payload = $jsonObj.payload
                    }

                    # Ensure that the object contains the verification result
                    if ($null -ne $payload.verificationResult) {
                        $isAvailable = $true                                        # V3

                        # See if the Secured Component Verification processing succeeded
                        if ($payload.verificationResult -eq 1) {
                            $indicatesSuccess = $true
                        }
                    }
                    elseif ($null -ne $payload.biosVerification) {
                        $isAvailable = $true                                        # V2

                        # See if the bios verification processing succeeded
                        if ($jsonObj.payload.biosVerification -eq "True") {
                            $indicatesSuccess = $true
                        }
                    }

                    # Verify that the service tag matches
                    $localSvcTag = Get-ServiceTag
                    if ($jsonObj.payload -is [string]) {
                        $payloadSvcTag = $payload.ServiceTag                        # V3
                    }
                    else {
                        $payloadSvcTag = Get-PayloadServiceTag -jsonObj $jsonObj    # V2
                    }

                    # The service tags must match for validation to succeed
                    if ($localSvcTag -ne $payloadSvcTag) {
                        Write-Warning "Local Service Tag=${localSvcTag}, Remote Service Tag=${payloadSvcTag}"
                        throw "Service tag contained in the BIOS Verification result does not match the service tag for the local machine."
                    }

                    # Extract the BV result age in days
                    $currentTimeUtc = Get-CurrentTimeInUtc
                    if ($jsonObj.payload -is [string]) {
                         $serverPayloadTime = Get-DateTimeFromString -dateString $payload.timeStamp -formatString "yyyy-MM-ddTHH:mm:ss.fffffffK"     # V3
                    }
                    else {
                        $serverPayloadTime = Get-DateTimeFromString -dateString $jsonObj.payload.timeStamp -formatString "MM/dd/yyyy HH:mm:ss"      # V2
                    }
                    $dateDiff = $currentTimeUtc.Subtract($serverPayloadTime)
                    $resultAgeInDays = $dateDiff.Days

                    # Extract the signing cert from the result payload
                    $payloadCert = $null

					if ($null -ne $jsonObj.signature -and $null -ne $jsonObj.signature.X509 -and $jsonObj.signature.X509 -is [string]) {	# V3
						$payloadCert = Get-DecodedCert -base64EncodedCert $jsonObj.signature.X509					
					}
					else {									    # V2
						if ($null -ne $jsonObj.signature -and $null -ne $jsonObj.signature.X509 -and $jsonObj.signature.X509.Count -gt 0) {
							$payloadCert = Get-DecodedCert -base64EncodedCert $jsonObj.signature.X509[0]
						}
					}

                    if ($null -ne $payloadCert) {
                        # Dump some cert properties
                        ##Show-Certificate -identifier "Payload Signing" -cert $payloadCert

                        # Verify that the cryptographic signature is valid
                        if ($jsonObj.payload -is [string]) {
                            $jsonPayload = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($jsonObj.payload))   # V3
                        }
                        else {
						    $jsonPayload = $jsonObj.payload | ConvertTo-Json -Compress -Depth 100                           # V2
                        }
                        $signatureIsValid = Test-PayloadSignature -jsonObj $jsonObj -jsonPayload $jsonPayload -signingCert $payloadCert

                        ##Write-Warning "Payload Time: ${serverPayloadTime}"

                        # Verify that the signature was generated when the certificate was valid
                        if ($serverPayloadTime -lt $payloadCert.NotBefore -or $serverPayloadTime -gt $payloadCert.NotAfter) {
                            throw "DTD Cloud Service signed the BIOS Verification result with an invalid certificate."
                        }

                        # The payload signature validation must succeed
                        if ($true -eq $signatureIsValid) {
                            # Request the cert chain
                            $certChain = Get-PluginSigningCertChain -cert $payloadCert -version $version
                            ##Write-Warning "CertChain: ${certChain}"

                            # Ensure that a valid certificate chain was returned by the DTD Cloud service
                            if ($null -eq $certChain) {
                                throw "DTD Cloud Service did not return a valid signing certificate chain."
                            }

                            # Test the certificate chain
                            Test-SigningCertificateChain -certChain $certChain

                            # Everything looks good, so indicate that the source is valid
                            $sourceIsValid = $true;
                        }
                        else {
                            Write-Warning "BIOS Verification result failed signature validation."
                        }
                    }
                    else {
                        Write-Warning "BIOS Verification result did not include a signing certificate."
                    }
                }
                else {
                    Write-Warning "BIOS Verification result did not contain the payload information."
                }
            }
            catch {
                Write-Warning "Exception occurred during processing of BIOS Verification result: ${_}"
            }
        }
        else {
            Write-Warning "Failed to retrieve any BIOS Verification results."
        }

        # Build the details object
        New-Object -TypeName DtdBvResultDetails -ArgumentList (
            $isAvailable, $sourceIsValid, $indicatesSuccess, $errorCode, $resultAgeInDays, $resultSourceName,
            $tamperingDetected, $biosIsInvalid, $biosNotSupported, $clientErrorOccurred, $serverErrorOccurred)
    }
}

# Wrap this system function so that it can be mocked
function Get-FromUnixTimeSecond {
    [CmdletBinding()]
    [OutputType([System.DateTimeOffset])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$unixTimeSeconds
    )

    begin {
    }
	
	process {
		$payloadTime = [System.DateTimeOffset]::FromUnixTimeSeconds($unixTimeSeconds)
		
		$payloadTime
	}
}

# Acquires the Intel ME Verification result details
function Get-DellMEvResult {
    [CmdletBinding()]
    [OutputType([DtdMEvResultDetails])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$version
    )

    begin {
    }

    process {
        # Default values
        $mevResultContent = ""
        $isAvailable = $false
        $sourceIsValid = $false
        $resultSourceName = "unknown"
        $indicatesSuccess = $false
        $errorCode = 0    # Default to success, since this value will not be present for Registry or File results
        $resultAgeInDays = 0
        $tamperingDetected = $false
        $meIsInvalid = $false
        $meNotSupported = $false
        $clientErrorOccurred = $false
        $serverErrorOccurred = $false

        # Retrieve the MEV result string via the IPC, if possible
        try {
            $mevIpcResult = Get-PluginResultsFromIPC([GUID]"CB18BDDF-94DD-44E1-84CB-69912CBBC9A3")
        }
        catch {
            Write-Warning "Exception occurred during request for ME Verification from the Dell Trusted Device service: ${_}"
        }
        
        if ($null -ne $mevIpcResult) {
            # Save the result source if the processing succeeded
            $resultSourceName = "service"

            # Save the content and error code returned
            $mevResultContent = $mevIpcResult.ResultJson
            $errorCode = $mevIpcResult.ErrorCode

            # Interpret the error code values
            if ($errorCode -ne 0 -and $errorCode -ne 99) {		# Success / ValidationSucceeded
                if ($errorCode -eq 1) {							# ValidationFailed
                    Write-Warning "Dell Trusted Device service indicated that the ME is invalid during ME Verification."
                    $meIsInvalid = $true
                }
                elseif ($errorCode -eq 2) {						# TamperingDetected
                    Write-Warning "Dell Trusted Device service indicated that tampering was detected during ME Verification."
                    $tamperingDetected = $true
                }
                elseif ($errorCode -eq 11) {						# PlatformUnsupported
                    Write-Warning "Dell Trusted Device service indicated that the ME is not supported during ME Verification."
                    $meNotSupported = $true
                }
                elseif ($errorCode -eq 7 -or $errorCode -eq 13) {	# ServerInternalError / NetworkConnectionError
                    Write-Warning "Dell Trusted Device service indicated that a server error occurred during ME Verification."
                    $serverErrorOccurred = $true
                }
                else {
                    # Otherwise, this is a client error
                    Write-Warning "Dell Trusted Device service indicated that a client error occurred during ME Verification."
                    $clientErrorOccurred = $true
                }
            }
        }
        else {
            # If the IPC failed, try the Registry
            Write-Warning "Falling back to Registry for Intel ME Verification result"

            try {
                $registryContent = Get-PluginResultsFromRegistry("CB18BDDF-94DD-44E1-84CB-69912CBBC9A3")
            }
            catch {
                Write-Warning "Exception occurred during retrieval of Intel ME Verification from the Registry: ${_}"
            }

            if (![string]::IsNullOrWhiteSpace($registryContent)) {
                $resultSourceName = "registry"
                $mevResultContent = $registryContent
            }
            else {
			    # If the registry failed, check the filesystem
			    Write-Warning "Falling back to filesystem for Intel ME Verification result"

			    try {
				    $fileSystemContent = Get-PluginResultsFromFile("CB18BDDF-94DD-44E1-84CB-69912CBBC9A3")
			    }
			    catch {
				    Write-Warning "Exception occurred during retrieval of Intel ME Verification results from the filesystem: ${_}"
			    }

			    if (![string]::IsNullOrWhiteSpace($fileSystemContent)) {
				    $resultSourceName = "filesystem"
				    $mevResultContent = $fileSystemContent
			    }
				else {
					$errorCode = 11    # Platform not supported
					$meNotSupported = $true
				}
            }
        }

        ##Write-Warning "MEV Result: ${mevResultContent}"
        
        # Ensure that we received some kind of content
        if (![string]::IsNullOrWhiteSpace($mevResultContent)) {
            # Catch all exceptions that occur while processing the MEV Result content
            try {
                # Turn the JSON string into an object
                try {
                    $jsonObj = ConvertFrom-Json $mevResultContent
                }
                catch {
                    throw "Failed to parse ME Verification result: ${_}"
                }

                # Ensure that a payload is present in the JSON object
                if ($null -ne $jsonObj.payload) {
					$payloadText = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($jsonObj.payload))
					$payload = ConvertFrom-Json $payloadText
                    # Ensure that the object contains the verification result
                    if ($null -ne $payload.result) {
                        $isAvailable = $true				# V2

                        # See if the ME verification processing succeeded
                        if ($payload.result -eq "True") {
                            $indicatesSuccess = $true
                        }
                    }
                    elseif ($null -ne $payload.verificationResult) {
                        $isAvailable = $true				# V3

                        # See if the ME verification processing succeeded
                        if ($payload.verificationResult -eq 1) {
                            $indicatesSuccess = $true
                        }
                    }

                    # Verify that the service tag matches
                    $localSvcTag = Get-ServiceTag
                    $payloadSvcTag = $payload.serviceTag

                    # The service tags must match for validation to succeed
                    if ($localSvcTag -ne $payloadSvcTag) {
                        Write-Warning "Local Service Tag=${localSvcTag}, Remote Service Tag=${payloadSvcTag}"
                        throw "Service tag contained in the ME Verification result does not match the service tag for the local machine."
                    }

                    # Extract the MEV result age in days
                    $currentTimeUtc = Get-CurrentTimeInUtc
					if ($null -ne $payload.result -or $null -ne $payload.clientNonce) {		# V2
						$serverPayloadTime = Get-FromUnixTimeSecond -unixTimeSeconds $payload.timeStamp
						$dateDiff = $currentTimeUtc.Subtract($serverPayloadTime.UtcDateTime)
					}
					else {									# V3
						$serverPayloadTime = Get-DateTimeFromString -dateString $payload.timeStamp -formatString "yyyy-MM-ddTHH:mm:ss.fffffffK"
						$dateDiff = $currentTimeUtc.Subtract($serverPayloadTime)
					}
                    $resultAgeInDays = $dateDiff.Days

                    # Extract the signing cert from the result payload
                    $payloadCert = $null
					
					if ($null -ne $jsonObj.signature -and $null -ne $jsonObj.signature.X509 -and $jsonObj.signature.X509 -is [string]) {	# V2
						if ($null -ne $jsonObj.signature -and $null -ne $jsonObj.signature.X509) {
							$payloadCert = Get-DecodedCert -base64EncodedCert $jsonObj.signature.X509					
						}
					}
					else {									# V3
						if ($null -ne $jsonObj.signature -and $null -ne $jsonObj.signature.X509 -and $jsonObj.signature.X509.Count -gt 0) {
							$payloadCert = Get-DecodedCert -base64EncodedCert $jsonObj.signature.X509[0]
						}
					}

                    if ($null -ne $payloadCert) {
                        # Dump some cert properties
                        ##Show-Certificate -identifier "Payload Signing" -cert $payloadCert

                        # Verify that the cryptographic signature is valid
                        $signatureIsValid = Test-PayloadSignature -jsonObj $jsonObj -jsonPayload $payloadText -signingCert $payloadCert

                        ##Write-Warning "Payload Time: ${serverPayloadTime}"

                        # Verify that the signature was generated when the certificate was valid
                        if ($serverPayloadTime -lt $payloadCert.NotBefore -or $serverPayloadTime -gt $payloadCert.NotAfter) {
                            throw "DTD Cloud Service signed the ME Verification result with an invalid certificate."
                        }

                        # The payload signature validation must succeed
                        if ($true -eq $signatureIsValid) {
                            # Request the cert chain
                            $certChain = Get-PluginSigningCertChain -cert $payloadCert -version $version
                            ##Write-Warning "CertChain: ${certChain}"

                            # Ensure that a valid certificate chain was returned by the DTD Cloud service
                            if ($null -eq $certChain) {
                                throw "DTD Cloud Service did not return a valid signing certificate chain."
                            }

                            # Test the certificate chain
                            Test-SigningCertificateChain -certChain $certChain

                            # Everything looks good, so indicate that the source is valid
                            $sourceIsValid = $true;
                        }
                        else {
                            Write-Warning "ME Verification result failed signature validation."
                        }
                    }
                    else {
                        Write-Warning "ME Verification result did not include a signing certificate."
                    }
                }
                else {
                    Write-Warning "ME Verification result did not contain the payload information."
                }
            }
            catch {
                Write-Warning "Exception occurred during processing of ME Verification result: ${_}"
            }
        }
        else {
            Write-Warning "Failed to retrieve any ME Verification results."
        }

        # Build the details object
        New-Object -TypeName DtdMEvResultDetails -ArgumentList (
            $isAvailable, $sourceIsValid, $indicatesSuccess, $errorCode, $resultAgeInDays, $resultSourceName,
            $tamperingDetected, $meIsInvalid, $meNotSupported, $clientErrorOccurred, $serverErrorOccurred)
    }
}

# Acquires the Secured Component Verification result details
function Get-DellScvResult {
    [CmdletBinding()]
    [OutputType([DtdScvResultDetails])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$version
    )

    begin {
    }

    process {
        # Default values
        $scvResultContent = ""
        $isAvailable = $false
        $sourceIsValid = $false
        $resultSourceName = "unknown"
        $indicatesSuccess = $false
        $errorCode = 0    # Default to success, since this value will not be present for Registry or File results
        $resultAgeInDays = 0
        $tamperingDetected = $false
        $scvIsInvalid = $false
        $scvNotSupported = $false
        $clientErrorOccurred = $false
        $serverErrorOccurred = $false

        # Retrieve the SCV result string via the IPC, if possible
        try {
            $scvIpcResult = Get-PluginResultsFromIPC([GUID]"7178FB8E-2667-4A00-B16F-FB7A5F5C1937")
        }
        catch {
            Write-Warning "Exception occurred during request for Secured Component Verification from the Dell Trusted Device service: ${_}"
        }
        
        if ($null -ne $scvIpcResult) {
            # Save the result source if the processing succeeded
            $resultSourceName = "service"

            # Save the content and error code returned
            $scvResultContent = $scvIpcResult.ResultJson
            $errorCode = $scvIpcResult.ErrorCode

            # Interpret the error code values
            if ($errorCode -ne 0 -and $errorCode -ne 99) {			# Success / ValidationSucceeded
                if ($errorCode -eq 1) {								# ValidationFailed
                    Write-Warning "Dell Trusted Device service indicated that the SCV is invalid during Secured Component Verification."
                    $scvIsInvalid = $true
                }
                elseif ($errorCode -eq 2) {							# TamperingDetected
                    Write-Warning "Dell Trusted Device service indicated that tampering was detected during Secured Component Verification."
                    $tamperingDetected = $true
                }
                elseif ($errorCode -eq 11) {						# PlatformUnsupported
                    Write-Warning "Dell Trusted Device service indicated that the SCV is not supported during Secured Component Verification."
                    $scvNotSupported = $true
                }
                elseif ($errorCode -eq 7 -or $errorCode -eq 13) {	# ServerInternalError / NetworkConnectionError
                    Write-Warning "Dell Trusted Device service indicated that a server error occurred during Secured Component Verification."
                    $serverErrorOccurred = $true
                }
                else {
                    # Otherwise, this is a client error
                    Write-Warning "Dell Trusted Device service indicated that a client error occurred during Secured Component Verification."
                    $clientErrorOccurred = $true
                }
            }
        }
        else {
            # If the IPC failed, try the Registry
            Write-Warning "Falling back to Registry for Secured Component Verification result"

            try {
                $registryContent = Get-PluginResultsFromRegistry("7178FB8E-2667-4A00-B16F-FB7A5F5C1937")
            }
            catch {
                Write-Warning "Exception occurred during retrieval of Secured Component Verification from the Registry: ${_}"
            }

            if (![string]::IsNullOrWhiteSpace($registryContent)) {
                $resultSourceName = "registry"
                $scvResultContent = $registryContent
            }
            else {
			    # If the IPC failed, check the filesystem
			    Write-Warning "Falling back to filesystem for Secured Component Verification result"

			    try {
				    $fileSystemContent = Get-PluginResultsFromFile("7178FB8E-2667-4A00-B16F-FB7A5F5C1937")
			    }
			    catch {
				    Write-Warning "Exception occurred during retrieval of Secured Component Verification results from the filesystem: ${_}"
			    }

			    if (![string]::IsNullOrWhiteSpace($fileSystemContent)) {
				    $resultSourceName = "filesystem"
				    $scvResultContent = $fileSystemContent
			    }
				else {
					$errorCode = 11    # Platform not supported
					$scvNotSupported = $true
				}
            }
        }

        ##Write-Warning "SCV Result: ${scvResultContent}"
        
        # Ensure that we received some kind of content
        if (![string]::IsNullOrWhiteSpace($scvResultContent)) {
            # Catch all exceptions that occur while processing the SCV Result content
            try {
                # Turn the JSON string into an object
                try {
                    $jsonObj = ConvertFrom-Json $scvResultContent
                }
                catch {
                    throw "Failed to parse Secured Component Verification result: ${_}"
                }

                # Ensure that a payload is present in the JSON object
                if ($null -ne $jsonObj.payload) {
                    if ($jsonObj.payload -is [string]) {
					    $payloadText = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($jsonObj.payload))
					    $payload = ConvertFrom-Json $payloadText
                    }
                    else {
                        $payload = $jsonObj.payload
                    }

                    # Ensure that the object contains the verification result
                    if ($null -ne $payload.VerificationResult) {
                        $isAvailable = $true                # V2

                        # See if the ME verification processing succeeded
                        if ($payload.VerificationResult -eq 1) {
                            $indicatesSuccess = $true
                        }
                    }
                    elseif ($null -ne $payload.scvVerification) {
                        $isAvailable = $true                # V1

                        # See if the Secured Component Verification processing succeeded
                        if ($payload.scvVerification -eq $true) {
                            $indicatesSuccess = $true
                        }
                    }

                    # Verify that the service tag matches
                    if ($jsonObj.payload -is [string]) {
                        $localSvcTag = Get-ServiceTag       # V2
                        $payloadSvcTag = $payload.ServiceTag

                        if ($localSvcTag -ne $payloadSvcTag) {
                            Write-Warning "Local Service Tag=${localSvcTag}, Remote Service Tag=${payloadSvcTag}"
                            throw "Service tag contained in the Secured Component Verification result does not match the service tag for the local machine."
                        }
                    }

                    # Extract the SCV result age in days
                    $currentTimeUtc = Get-CurrentTimeInUtc
                    if ($jsonObj.payload -is [string]) {
						$serverPayloadTime = Get-DateTimeFromString -dateString $payload.timeStamp -formatString "yyyy-MM-ddTHH:mm:ss.fffffffK"    # V2
                    }
                    else {
                        $serverPayloadTime = Get-DateTimeFromString -dateString $payload.timeStamp -formatString "yyyyMMddTHHmmssZ"                 # V1
                    }
                    $dateDiff = $currentTimeUtc.Subtract($serverPayloadTime)
                    $resultAgeInDays = $dateDiff.Days

                    # Extract the signing cert from the result payload
                    $payloadCert = $null

                    if ($null -ne $jsonObj.signature -and $null -ne $jsonObj.signature.X509) {
                        $payloadCert = Get-DecodedCert -base64EncodedCert $jsonObj.signature.X509

                        # Dump some cert properties
                        ##Show-Certificate -identifier "Payload Signing" -cert $payloadCert

                        # Verify that the cryptographic signature is valid
                        if ($jsonObj.payload -is [string]) {
                            $jsonPayload = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($jsonObj.payload))   # V2
                        }
                        else {
						    $jsonPayload = $jsonObj.payload | ConvertTo-Json -Depth 100 -Compress                           # V1
                        }
                        $signatureIsValid = Test-PayloadSignature -jsonObj $jsonObj -jsonPayload $jsonPayload -signingCert $payloadCert

                        ##Write-Warning "Payload Time: ${serverPayloadTime}"

                        # Verify that the signature was generated when the certificate was valid
                        if ($serverPayloadTime -lt $payloadCert.NotBefore -or $serverPayloadTime -gt $payloadCert.NotAfter) {
                            throw "DTD Cloud Service signed the Secured Component Verification result with an invalid certificate."
                        }

                        # The payload signature validation must succeed
                        if ($true -eq $signatureIsValid) {
                            # Request the cert chain
                            $certChain = Get-PluginSigningCertChain -cert $payloadCert -version $version
                            ##Write-Warning "CertChain: ${certChain}"

                            # Ensure that a valid certificate chain was returned by the DTD Cloud service
                            if ($null -eq $certChain) {
                                throw "DTD Cloud Service did not return a valid signing certificate chain."
                            }

                            # Test the certificate chain
                            Test-SigningCertificateChain -certChain $certChain

                            # Everything looks good, so indicate that the source is valid
                            $sourceIsValid = $true;
                        }
                        else {
                            Write-Warning "Secured Component Verification result failed signature validation."
                        }
                    }
                    else {
                        Write-Warning "Secured Component Verification result did not include a signing certificate."
                    }
                }
                else {
                    Write-Warning "Secured Component Verification result did not contain the payload information."
                }
            }
            catch {
                Write-Warning "Exception occurred during processing of Secured Component Verification result: ${_}"
            }
        }
        else {
            Write-Warning "Failed to retrieve any Secured Component Verification results."
        }

        # Build the details object
        New-Object -TypeName DtdScvResultDetails -ArgumentList (
            $isAvailable, $sourceIsValid, $indicatesSuccess, $errorCode, $resultAgeInDays, $resultSourceName,
            $tamperingDetected, $scvIsInvalid, $scvNotSupported, $clientErrorOccurred, $serverErrorOccurred)
    }
}

function Get-ComponentUpdatesCveIds($payload) {
    $CveHighestScore = 0
    $criticalVulnerabilityCount = 0
    $highVulnerabilityCount = 0
    $mediumVulnerabilityCount = 0
    $lowVulnerabilityCount = 0
    $biosOutOfDate = $false
    $firmwareOutOfDate = $false

    # Traverse componentUpdates in the payload
    foreach ($componentUpdate in $payload.componentUpdates) {
        # Calculate vulnerability scores and counts
        foreach ($cveId in $componentUpdate.cveIds) {
            $cveScore = [double]$cveId.baseScore
            $CveHighestScore = [Math]::Max($CveHighestScore, $cveScore)

            if ($cveScore -ge 9.0) {
                $criticalVulnerabilityCount++
            }
            elseif ($cveScore -ge 7.0) {
                $highVulnerabilityCount++
            }
            elseif ($cveScore -ge 4.0) {
                $mediumVulnerabilityCount++
            }
            elseif ($cveScore -gt 0.0) {
                $lowVulnerabilityCount++
            }
        }

        # Check inventoryComponent and verificationResult for BIOS/Firmware status
        if ($componentUpdate.inventoryComponent.componentType -eq "BIOS" -and $componentUpdate.verificationResult -eq 0) {
            $biosOutOfDate = $true
        }
        elseif ($componentUpdate.inventoryComponent.componentType -eq "FRMW" -and $componentUpdate.verificationResult -eq 0) {
            $firmwareOutOfDate = $true
        }
    }

    # Return calculated results and status of BIOS/Firmware as comma-separated values
    return $CveHighestScore, $criticalVulnerabilityCount, $highVulnerabilityCount, $mediumVulnerabilityCount, $lowVulnerabilityCount, $biosOutOfDate, $firmwareOutOfDate
}

# Acquires the CVE Correlation result details
function Get-DellCveResult {
    [CmdletBinding()]
    [OutputType([DtdCveResultDetails])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]$version
    )

    begin {
    }

    process {
        # Default values
        $guid = "9C1A8B38-CDC9-45B6-807E-F5DFFB719308"
        $resultContent = ""
        $isAvailable = $false
        $sourceIsValid = $false
        $resultSourceName = "unknown"
        $indicatesSuccess = $false
        $errorCode = 0    # Default to success, since this value will not be present for Registry or File results
        $resultAgeInDays = 0
        $tamperingDetected = $false
        $biosIsInvalid = $false
        $biosNotSupported = $false
        $clientErrorOccurred = $false
        $serverErrorOccurred = $false
        $CveHighestScore = 0.0
        $criticalVulnerabilityCount = 0
        $highVulnerabilityCount = 0
        $mediumVulnerabilityCount = 0
        $lowVulnerabilityCount = 0
        $biosOutOfDate = $false
        $firmwareOutOfDate = $false

        # Retrieve the CVE Correlation result string via the IPC, if possible
        try {
            $ipcResult = Get-PluginResultsFromIPC([GUID]$guid)
        }
        catch {
            Write-Warning "Exception occurred during request for CVE Correlation from the Dell Trusted Device service: ${_}"
        }
        
        if ($null -ne $ipcResult) {
            # Save the result source if the processing succeeded
            $resultSourceName = "service"

            # Save the content and error code returned
            $resultContent = $ipcResult.ResultJson
            $errorCode = $ipcResult.ErrorCode

            # Interpret the error code values
            if ($errorCode -ne 0 -and $errorCode -ne 99) {		# Success / ValidationSucceeded
                if ($errorCode -eq 1) {							# ValidationFailed
                    Write-Warning "Dell Trusted Device service indicated that the BIOS is invalid during CVE Correlation."
                    $biosIsInvalid = $true
                }
                elseif ($errorCode -eq 2) {						# TamperingDetected
                    Write-Warning "Dell Trusted Device service indicated that tampering was detected during CVE Correlation."
                    $tamperingDetected = $true
                }
                elseif ($errorCode -eq 11) {						# PlatformUnsupported
                    Write-Warning "Dell Trusted Device service indicated that the BIOS is not supported during CVE Correlation."
                    $biosNotSupported = $true
                }
                elseif ($errorCode -eq 7 -or $errorCode -eq 13) {	# ServerInternalError / NetworkConnectionError
                    Write-Warning "Dell Trusted Device service indicated that a server error occurred during CVE Correlation."
                    $serverErrorOccurred = $true
                }
                else {
                    # Otherwise, this is a client error
                    Write-Warning "Dell Trusted Device service indicated that a client error occurred during CVE Correlation."
                    $clientErrorOccurred = $true
                }
            }
        }
        else {
            # If the IPC failed, try the Registry
            Write-Warning "Falling back to Registry for CVE Correlation result"

            try {
                $registryContent = Get-PluginResultsFromRegistry($guid)
            }
            catch {
                Write-Warning "Exception occurred during retrieval of CVE Correlation from the Registry: ${_}"
            }

            if (![string]::IsNullOrWhiteSpace($registryContent)) {
                $resultSourceName = "registry"
                $resultContent = $registryContent
            }
            else {
			    # If the registry failed, check the filesystem
			    Write-Warning "Falling back to filesystem for CVE Correlation result"

			    try {
				    $fileSystemContent = Get-PluginResultsFromFile($guid)
			    }
			    catch {
				    Write-Warning "Exception occurred during retrieval of CVE Correlation results from the filesystem: ${_}"
			    }

			    if (![string]::IsNullOrWhiteSpace($fileSystemContent)) {
				    $resultSourceName = "filesystem"
				    $resultContent = $fileSystemContent
			    }
				else {
					$errorCode = 11    # Platform not supported
					$biosNotSupported = $true
				}
            }
        }

        ##Write-Warning "CVE Correlation Result: ${resultContent}"
        
        # Ensure that we received some kind of content
        if (![string]::IsNullOrWhiteSpace($resultContent)) {
            # Catch all exceptions that occur while processing the CVE Correlation Result content
            try {
                # Turn the JSON string into an object
                try {
                    $jsonObj = ConvertFrom-Json $resultContent
                }
                catch {
                    throw "Failed to parse CVE Correlation result: ${_}"
                }

                # Ensure that a payload is present in the JSON object
                if ($null -ne $jsonObj.payload) {
					$payloadText = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($jsonObj.payload))
					$payload = ConvertFrom-Json $payloadText
                    # Ensure that the object contains the verification result
                    if ($null -ne $payload.verificationResult) {
                        $isAvailable = $true

                        # See if the CVE Correlation processing succeeded
                        if ($payload.verificationResult -eq 1) {
                            $indicatesSuccess = $true
                        }
                        else {
                            $biosOutOfDate = $true
                        }
                    }

                    # Verify that the service tag matches
                    $localSvcTag = Get-ServiceTag
                    $payloadSvcTag = $payload.serviceTag

                    # The service tags must match for validation to succeed
                    if ($localSvcTag -ne $payloadSvcTag) {
                        Write-Warning "Local Service Tag=${localSvcTag}, Remote Service Tag=${payloadSvcTag}"
                        throw "Service tag contained in the CVE Correlation result does not match the service tag for the local machine."
                    }

                    # Extract the CVE Correlation result age in days
                    $currentTimeUtc = Get-CurrentTimeInUtc
                    $serverPayloadTime = Get-DateTimeFromString -dateString $payload.timeStamp -formatString "yyyy-MM-ddTHH:mm:ss.fffffffK"
                    $dateDiff = $currentTimeUtc.Subtract($serverPayloadTime)
                    $resultAgeInDays = $dateDiff.Days

                    # Iterate through cveIds to calculate the vulnerability score and count
                    if ($null -ne $payload.cveIds) {
                        foreach ($cveId in $payload.cveIds) {
                            $cveScore = [double]$cveId.baseScore
                            $CveHighestScore = [Math]::Max($CveHighestScore, [double]$cveId.baseScore)

                            if ($cveScore -ge 9.0) {
                                $criticalVulnerabilityCount++
                            }
                            elseif ($cveScore -ge 7.0) {
                                $highVulnerabilityCount++
                            }
                            elseif ($cveScore -ge 4.0) {
                                $mediumVulnerabilityCount++
                            }
                            elseif ($cveScore -gt 0.0) {
                                $lowVulnerabilityCount++
                            }
                        }
                    }
                    else{
                        $CveHighestScore, $criticalVulnerabilityCount, $highVulnerabilityCount, $mediumVulnerabilityCount, $lowVulnerabilityCount, $biosOutOfDate, $firmwareOutOfDate = Get-ComponentUpdatesCveIds $payload
                    }

                    # Extract the signing cert from the result payload
                    $payloadCert = $null
                    if ($null -ne $jsonObj.signature -and $null -ne $jsonObj.signature.X509 -and $jsonObj.signature.X509 -is [string]) {
						$payloadCert = Get-DecodedCert -base64EncodedCert $jsonObj.signature.X509					
					}

                    if ($null -ne $payloadCert) {
                        # Dump some cert properties
                        ##Show-Certificate -identifier "Payload Signing" -cert $payloadCert

                        # Verify that the cryptographic signature is valid
                        $signatureIsValid = Test-PayloadSignature -jsonObj $jsonObj -jsonPayload $payloadText -signingCert $payloadCert

                        ##Write-Warning "Payload Time: ${serverPayloadTime}"

                        # Verify that the signature was generated when the certificate was valid
                        if ($serverPayloadTime -lt $payloadCert.NotBefore -or $serverPayloadTime -gt $payloadCert.NotAfter) {
                            throw "DTD Cloud Service signed the CVE Correlation result with an invalid certificate."
                        }

                        # The payload signature validation must succeed
                        if ($true -eq $signatureIsValid) {
                            # Request the cert chain
                            $certChain = Get-PluginSigningCertChain -cert $payloadCert -version $version
                            ##Write-Warning "CertChain: ${certChain}"

                            # Ensure that a valid certificate chain was returned by the DTD Cloud service
                            if ($null -eq $certChain) {
                                throw "DTD Cloud Service did not return a valid signing certificate chain."
                            }

                            # Test the certificate chain
                            Test-SigningCertificateChain -certChain $certChain

                            # Everything looks good, so indicate that the source is valid
                            $sourceIsValid = $true;
                        }
                        else {
                            Write-Warning "CVE Correlation result failed signature validation."
                        }
                    }
                    else {
                        Write-Warning "CVE Correlation result did not include a signing certificate."
                    }
                }
                else {
                    Write-Warning "CVE Correlation result did not contain the payload information."
                }
            }
            catch {
                Write-Warning "Exception occurred during processing of CVE Correlation result: ${_}"
            }
        }
        else {
            Write-Warning "Failed to retrieve any CVE Correlation results."
        }

        # Build the details object
        New-Object -TypeName DtdCveResultDetails -ArgumentList (
            $isAvailable, $sourceIsValid, $indicatesSuccess, $errorCode, $resultAgeInDays, $resultSourceName,
            $tamperingDetected, $biosIsInvalid, $biosNotSupported, $clientErrorOccurred, $serverErrorOccurred,
            $CveHighestScore, $criticalVulnerabilityCount, $highVulnerabilityCount,
            $mediumVulnerabilityCount, $lowVulnerabilityCount, $biosOutOfDate, $firmwareOutOfDate)
    }
}

# Get the full DTD product, service, and driver status
function Get-DtdInformation {
    [CmdletBinding()]
    [OutputType([DtdFullDetails])]
    param (
    )

    begin {
    }

    process {
        # Store all of the information in a single object
        $dtdFullDetails = New-Object -TypeName DtdFullDetails

        # Retrieve the DTD product-level information
        $productDetails = Get-DtdProductInformation
        if ($true -eq $productDetails.IsInstalled) {
            # Copy details into the output object
            $dtdFullDetails.DtdProductInstalled = $true
            $dtdFullDetails.DtdProductVersion = $productDetails.Version

            # Retrieve the service information
            $serviceDetails = Get-DtdServiceInformation
            if ($true -eq $serviceDetails.IsInstalled) {
                # Copy details into the output object
                $dtdFullDetails.DtdServiceInstalled = $true
                $dtdFullDetails.DtdServiceVersion = $serviceDetails.Version
                $dtdFullDetails.DtdServiceIsSignatureValid = $serviceDetails.SignatureIsValid
                $dtdFullDetails.DtdServiceIsRunning = $serviceDetails.IsRunning
                $dtdFullDetails.DtdServiceIsAutoStart = $serviceDetails.IsAutoStart
                $dtdFullDetails.DtdServiceIsStoppable = $serviceDetails.IsStoppable
            }
            else {
                # Mark this as being missing
                $dtdFullDetails.DtdServiceInstalled = $false
            }

            # Retrieve the dtdsel information
            $dtdselDetails = Get-DtdSelDriverInformation
            if ($true -eq $dtdselDetails.IsInstalled) {
                # Copy details into the output object
                $dtdFullDetails.DtdSelDriverInstalled = $true
                $dtdFullDetails.DtdSelDriverVersion = $dtdselDetails.Version
                $dtdFullDetails.DtdSelDriverSignatureIsValid = $dtdselDetails.SignatureIsValid
                $dtdFullDetails.DtdSelDriverIsRunning = $dtdselDetails.IsRunning
                $dtdFullDetails.DtdSelDriverIsSystemStart = $dtdselDetails.IsSystemStart
            }
            else {
                # Mark this as being missing
                $dtdFullDetails.DtdSelDriverInstalled = $false
            }

            # Retrieve the dellbv information
            $dellbvDetails = Get-DellBvDriverInformation
            if ($true -eq $dellbvDetails.IsInstalled) {
                # Copy details into the output object
                $dtdFullDetails.DellBvDriverInstalled = $true
                $dtdFullDetails.DellBvDriverVersion = $dellbvDetails.Version
                $dtdFullDetails.DellBvDriverSignatureIsValid = $dellbvDetails.SignatureIsValid
                $dtdFullDetails.DellBvDriverIsDemandStart = $dellbvDetails.IsManualStart
            }
            else {
                # Mark this as being missing
                $dtdFullDetails.DellBvDriverInstalled = $false
            }

            # Retrieve the BV results
            $bvResult = Get-DellBvResult -version $productDetails.Version
			
            # Copy details into the output object
            $dtdFullDetails.BvResultAvailable = $bvResult.IsAvailable
            $dtdFullDetails.BvResultSourceName = $bvResult.SourceName
            $dtdFullDetails.BvResultSourceIsValid = $bvResult.SourceIsValid
            $dtdFullDetails.BvResult = $bvResult.Outcome
            $dtdFullDetails.BvResultAgeInDays = $bvResult.AgeInDays

            # Set BV result error code values regardless of the result availability
            $dtdFullDetails.BvResultErrorCode = $bvResult.ErrorCode
            $dtdFullDetails.BvResultIndicatesTampering = $bvResult.TamperingDetected
            $dtdFullDetails.BvResultBiosIsInvalid = $bvResult.BiosIsInvalid
            $dtdFullDetails.BvResultBiosNotSupported = $bvResult.BiosNotSupported
            $dtdFullDetails.BvResultClientErrorOccurred = $bvResult.ClientErrorOccurred
            $dtdFullDetails.BvResultServerErrorOccurred = $bvResult.ServerErrorOccurred
			
            $mevResult = Get-DellMEvResult -version $productDetails.Version
			
            # Copy details into the output object
            $dtdFullDetails.MEvResultAvailable = $mevResult.IsAvailable
            $dtdFullDetails.MEvResultSourceName = $mevResult.SourceName
            $dtdFullDetails.MEvResultSourceIsValid = $mevResult.SourceIsValid
            $dtdFullDetails.MEvResult = $mevResult.Outcome
            $dtdFullDetails.MEvResultAgeInDays = $mevResult.AgeInDays

            # Set MEV result error code values regardless of the result availability
            $dtdFullDetails.MEvResultErrorCode = $mevResult.ErrorCode
            $dtdFullDetails.MEvResultIndicatesTampering = $mevResult.TamperingDetected
            $dtdFullDetails.MEvResultMEIsInvalid = $mevResult.MEIsInvalid
            $dtdFullDetails.MEvResultMENotSupported = $mevResult.MENotSupported
            $dtdFullDetails.MEvResultClientErrorOccurred = $mevResult.ClientErrorOccurred
            $dtdFullDetails.MEvResultServerErrorOccurred = $mevResult.ServerErrorOccurred

			$scvResult = Get-DellScvResult -version $productDetails.Version
			
            # Copy details into the output object
            $dtdFullDetails.SCvResultAvailable = $scvResult.IsAvailable
            $dtdFullDetails.SCvResultSourceName = $scvResult.SourceName
            $dtdFullDetails.SCvResultSourceIsValid = $scvResult.SourceIsValid
            $dtdFullDetails.SCvResult = $scvResult.Outcome
            $dtdFullDetails.SCvResultAgeInDays = $scvResult.AgeInDays

            # Set SCV result error code values regardless of the result availability
            $dtdFullDetails.SCvResultErrorCode = $scvResult.ErrorCode
            $dtdFullDetails.SCvResultIndicatesTampering = $scvResult.TamperingDetected
            $dtdFullDetails.SCvResultIsInvalid = $scvResult.ScvIsInvalid
            $dtdFullDetails.SCvResultNotSupported = $scvResult.ScvNotSupported
            $dtdFullDetails.SCvResultClientErrorOccurred = $scvResult.ClientErrorOccurred
            $dtdFullDetails.SCvResultServerErrorOccurred = $scvResult.ServerErrorOccurred

            # Retrieve the CVE Correlation results
            $bvResult = Get-DellCveResult -version $productDetails.Version
			
            # Copy details into the output object
            $dtdFullDetails.CveResultAvailable = $bvResult.IsAvailable
            $dtdFullDetails.CveResultSourceName = $bvResult.SourceName
            $dtdFullDetails.CveResultSourceIsValid = $bvResult.SourceIsValid
            $dtdFullDetails.CveResult = $bvResult.Outcome
            $dtdFullDetails.CveResultAgeInDays = $bvResult.AgeInDays
            $dtdFullDetails.CveHighestScore = $bvResult.CveHighestScore

            # Set CVE Correlation result error code values regardless of the result availability
            $dtdFullDetails.CveResultErrorCode = $bvResult.ErrorCode
            $dtdFullDetails.CveResultIndicatesTampering = $bvResult.TamperingDetected
            $dtdFullDetails.CveResultBiosIsInvalid = $bvResult.BiosIsInvalid
            $dtdFullDetails.CveResultBiosNotSupported = $bvResult.BiosNotSupported
            $dtdFullDetails.CveResultClientErrorOccurred = $bvResult.ClientErrorOccurred
            $dtdFullDetails.CveResultServerErrorOccurred = $bvResult.ServerErrorOccurred

            # Copy additional details into the output object
            $dtdFullDetails.CveCriticalCount = $bvResult.CriticalVulnerabilityCount
            $dtdFullDetails.CveHighCount = $bvResult.HighVulnerabilityCount
            $dtdFullDetails.CveMediumCount = $bvResult.MediumVulnerabilityCount
            $dtdFullDetails.CveLowCount = $bvResult.LowVulnerabilityCount
            $dtdFullDetails.BiosOutOfDate = $bvResult.BiosOutOfDate
            $dtdFullDetails.FirmwareOutOfDate = $bvResult.FirmwareOutOfDate
        }
        else {
            # Mark this as being missing
            $dtdFullDetails.DtdProductInstalled = $false
        }

        # Set the script execution status result if we got this far without errors
        $dtdFullDetails.ScriptExecutedWithoutExceptions = $true
        $dtdFullDetails.ScriptExceptionMessage = ""

        # Return the finalized object
        $dtdFullDetails
    }
}

$addTrailingZero = $false
# Converts our object into JSON
function Get-EncodedDtdInformation {
    [CmdletBinding()]
    [OutputType([string])]
    param (
    )
    $data = Get-DtdInformation
    #Microsoft Intune has strict rule checking for the Data Types of each compliance setting. 
    #Unfortunately, this means that if a number is a whole number, it must have a trailing 0, as it will refuse to cast an Int64 to a Double.
    #Check if the Highest Vulnerability Score has a trailing 0
    if ($data.CveHighestScore -eq [math]::floor($data.CveHighestScore)) {
        $addTrailingZero = $true
    }
    # Convert the details object to JSON and return it
    $content = $data | ConvertTo-Json -Compress -Depth 100

    #If addTrailingZero is true, add a trailing 0 to the highest vulnerability score by formatting it to 1 decimal place
    if ($addTrailingZero) {
        $content = $content -replace '^"CveHighestScore":(\d+)', '"CveHighestScore":$1.0'
    }
    return $content
}

# Main execution function
function Get-TrustedDeviceResultsForMEM {
    [CmdletBinding()]
    [OutputType([string])]
    param (
    )

    # Ensure that a valid output JSON object is returned even if exceptions occur during processing
    try {
        # Retrieve the encoded result of all product/service/driver details
        $outputJson = Get-EncodedDtdInformation
    }
    catch {
        Write-Warning "An exception occurred during script processing: ${_}"

        # Exception occurred, so output an object that indicates failures occurred.
        $dtdErrorDetails = New-Object -TypeName DtdFullDetails
        $dtdErrorDetails.ScriptExecutedWithoutExceptions = $false
        $dtdErrorDetails.ScriptExceptionMessage = $_

        $outputJson = $dtdErrorDetails | ConvertTo-Json -Compress -Depth 100
    }

    $outputJson
}

return Get-TrustedDeviceResultsForMEM
