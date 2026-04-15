# 1. Connect to Exchange Online
Connect-ExchangeOnline

# 2. Define the User
$User = "user@yourdomain.com"

# 3. Export Diagnostic Logs and Parse XML for ELC (Retention/Archive) Properties
[xml]$diag = (Export-MailboxDiagnosticLogs -Identity $User -ExtendedProperties).MailboxLog

# 4. Extract specific timestamps related to the Managed Folder Assistant (MFA)
$diag.Properties.MailboxTable.Property | Where-Object {$_.Name -like "ELC*"} | Select-Object Name, Value
