# Stop the time service
Stop-Service w32time

# Unregister and re-register the service to clear corrupted state
w32tm /unregister
w32tm /register

# Start the time service
Start-Service w32time

# Configure time.nist.gov with 0x8 (SpecialInterval) or 0x1
w32tm /config /manualpeerlist:"time.nist.gov,0x8" /syncfromflags:manual /reliable:YES /update

# Restart service to force config reload
Restart-Service w32time

# Force time resync and rediscovery
w32tm /resync /rediscover