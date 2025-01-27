# Reset Computer Machine Password (run from affected machine.) Username can be changed if necessary. Enter password at prompt.
Reset-ComputerMachinePassword -Server spc-dc01 -Credential SUPERIORPAVING\Administrator
# Repair SChannel Communication with DC 
Test-ComputerSecureChannel -Repair -Credential SUPERIORPAVING\Administrator
# Test SChannel Communication with DC
nltest /sc_verify:domain.tld