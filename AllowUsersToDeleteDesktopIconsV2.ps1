# Get the path to the Public Desktop folder
$publicDesktop = "$env:PUBLIC\Desktop"

# Define the ACL (Access Control List) for the Users group
$acl = Get-Acl -Path $publicDesktop
$permission = "BUILTIN\Users", "Modify", "Allow"
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission

# Add the new rule to the folder's ACL
$acl.AddAccessRule($accessRule)

# Apply the new ACL to the folder
Set-Acl -Path $publicDesktop -AclObject $acl