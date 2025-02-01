function ConvertFrom-EncryptedAdobeKey {
    [CmdletBinding()]
    Param(
        [Parameter(Position=0, Mandatory=$true)] 
        [string]
        [ValidateLength(24,24)]
        $EncryptedKey
    )

    $AdobeCipher = "0000000001", "5038647192", "1456053789", "2604371895",
        "4753896210", "8145962073", "0319728564", "7901235846",
        "7901235846", "0319728564", "8145962073", "4753896210",
        "2604371895", "1426053789", "5038647192", "3267408951",
        "5038647192", "2604371895", "8145962073", "7901235846",
        "3267408951", "1426053789", "4753896210", "0319728564"
       
    $counter = 0

    $DecryptedKey = ""

    While ($counter -ne 24) {
        $DecryptedKey += $AdobeCipher[$counter].substring($EncryptedKey.SubString($counter, 1), 1)
        $counter ++
    }

    $DecryptedKey
    
#    .SYNOPSIS
#    Converts encrypted key for adobe products to decrypted key used to install application.
#
#    .DESCRIPTION
#    Converts encrypted key for adobe products to decrypted key used to install application.
#
#    The encrypted key can be found in the registry under the Local Machine hive, under software, adobe, 
#    then the product you are looking for (IE, Acrobat), the version you are looking for (IE. 7.0),
#    then the Registration key.  Just copy from there and paste as the input for the function.
#
#    .PARAMETER EncryptedKey
#    The encrypted version of the adobe key found in the registry.
#
#    .OUTPUTS
#    System.String. Returns the decrypted key in a string object.
#
#    .EXAMPLE
#    C:\PS> ConvertFrom-EncryptedAdobeKey.ps1 123456789012345678901234
#    036392546015404819372237

}