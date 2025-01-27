# Reverts login script to original after email signature has been set
Import-Module ActiveDirectory
Get-ADUser -Filter * -searchbase "OU=Density Technicians,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Executive,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Accounting,OU=Office,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Human Resources,OU=Office,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath hrlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Marketing,OU=Office,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath estimatorlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Safety,OU=Office,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Reception,OU=Office,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=Operations,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "CN=Angie Fadely,OU=Shop,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "CN=Albert Snyder,OU=Shop,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "CN=Rocky Miller,OU=Shop,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "CN=Ralph Sine,OU=Shop,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "CN=Kirby Lambert,OU=Shop,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath bristowlogon.vbs –PassThru
Get-ADUser -Filter * -searchbase "OU=STC,OU=Superior Paving Employees,DC=superiorpaving,DC=net" -properties scriptpath | Set-ADUser -scriptpath Trucking2.vbs –PassThru