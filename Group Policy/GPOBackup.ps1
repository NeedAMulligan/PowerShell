# Backup all GPO
$date = Get-Date -Format yyyyMMdd
New-Item C:\GPO_Backup -ItemType Directory
New-Item C:\GPO_Backup\$date -ItemType Directory
$GPOS = Get-GPO -All | Select DisplayName
foreach ($GPO in $GPOS) {
    New-Item C:\GPO_Backup\$date\$GPO -ItemType Directory
    Backup-GPO -Name $GPO.Displayname -Path C:\GPO_Backup\$date\$GPO
}