Import-Module ActiveDirectory
// Changes login script to update email signature with new address
Get-ADUser -Filter * -searchbase "OU=Density Technicians,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Executive,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Accounting,OU=Office,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Human Resources,OU=Office,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Marketing,OU=Office,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath estimatorlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Safety,OU=Office,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Reception,OU=Office,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Operations,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "CN=Angie Fadely,OU=Shop,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "CN=Heston Luttrell,OU=Shop,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "CN=Rocky Miller,OU=Shop,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "CN=Ralph Sine,OU=Shop,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "CN=Kirby Lambert,OU=Shop,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon2.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=STC,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath Trucking2.vbs –PassThru