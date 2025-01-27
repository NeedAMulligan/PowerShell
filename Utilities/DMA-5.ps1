Get-WinEvent -ListLog * | 
  foreach-Object { get-winevent @{logname=$_.logname; starttime='2:45 pm' } -ea 0 } |
  Where-Object message -match 'DMA'