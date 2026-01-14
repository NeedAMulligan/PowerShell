Repair-WindowsImage -Online -RestoreHealth

# see logs in realtime for DISM process #

Get-Content -Path C:\Windows\Logs\DISM\dism.log -Wait
