# retrieve the machine passphrase from the SentinelOne console
# open an administrative command prompt and run 
cd "c:\program files\sentinelone\sentinel agent 22.2.4.558\"
sentinelctl.exe unprotect -k "passphrase"
sentinelctl.exe unload -slam -k "passphrase"
sentinelctl.exe config -p vssConfig.vssProtection -v false
vssadmin Resize ShadowStorage /For=C: /On=C: /MaxSize=5%
sentinelctl.exe config -p vssConfig.vssProtection -v true
sentinelctl.exe load -slam
sentinelctl.exe load protect