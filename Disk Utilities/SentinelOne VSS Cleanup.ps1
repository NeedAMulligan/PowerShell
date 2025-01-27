# retrieve the machine passphrase from the SentinelOne console
# open an administrative command prompt and run 
#
# Define variables
#
# Locate Sentinelctl.exe
$sentinelctl = where.exe /r 'C:\Program Files\SentinelOne' sentinelctl

# Define SentinelOne machine passphrase. Can be obtained from SentinelOne portal (edit this variable before running.)
$passphrase = "PASSPHRASE"

# Get SentinelOne status
& $sentinelctl status

# Turn off SentinelOne protection
& $sentinelctl unprotect -k $passphrase 

# Unload SentinelOne
& $sentinelctl unload -slam -k $passphrase

# Turn off SentinelOne VSS Protection
& $sentinelctl config -p vssConfig.vssProtection -v false

# Resize shadow storage (adjust percentage as needed)
vssadmin Resize ShadowStorage /For=C: /On=C: /MaxSize=2%

# Turn on SentinelOne VSS protection
& $sentinelctl config -p vssConfig.vssProtection -v true

# Reload SentinelOne
& $sentinelctl load -slam

# Turn on SentinelOne protection
& $sentinelctl protect

# Get SentinelOne status
& $sentinelctl status