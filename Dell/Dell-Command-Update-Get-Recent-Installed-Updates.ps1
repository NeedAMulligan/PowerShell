$LogPath = "C:\ProgramData\Dell\UpdateService\Log"

Get-ChildItem $LogPath -Filter "*.log" |
  Sort-Object LastWriteTime -Descending |
  Select-String -Pattern "successfully installed|installed successfully" |
  ForEach-Object {
    [PSCustomObject]@{
      LogFile = Split-Path $_.Path -Leaf
      Line    = $_.Line.Trim()
    }
  }
