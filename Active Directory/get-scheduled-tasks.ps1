$cred = Get-Credential 
$comp = "ewa-computer-name" 
$session = New-PSSession -ComputerName $comp -Credential $cred 
$script = { 
"Services:"  
Get-WmiObject win32_service  -ErrorAction Stop| where {$_.StartMode -like 'Auto' -and $_.Startname -notlike '*local*' -and $_.Startname -notlike '*NT AU*'}| Select-Object Name, DisplayName, State, StartMode, StartName | Format-Table -Property * -AutoSize| Out-String -Width 4096 
# To output to CSV, add this string to the previous command: | Export-Csv c:\Out\filename.csv - NoTypeInformation  

"ScheduledTasks"  
schtasks.exe /query /V /FO CSV | ConvertFrom-Csv | Where { $_.TaskName -ne "TaskName"  -and $_.TaskName -like "*powershell*"}|Select-Object @{ label='Name';     expression={split-path $_.taskname -Leaf} }, Author ,'run as user','task to run'| Format-Table -Property * -AutoSize| Out-String -Width 4096 
# To export to CSV, add this string to the previous command: | Export-Csv c:\users\eberndt\desktop\tasks.csv - NoTypeInformation  
}  
Invoke-Command -Session $session -ScriptBlock $script