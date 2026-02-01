#Remove pesky Windows 10 pre-installed apps at login time
#Updated June 2017 - 1703 Build
Get-AppxPackage *3dbuilder* | Remove-AppxPackage
Get-AppxPackage *officehub* | Remove-AppxPackage
Get-AppxPackage *skypeapp* | Remove-AppxPackage
Get-AppxPackage *getstarted* | Remove-AppxPackage
Get-AppxPackage *zunemusic* | Remove-AppxPackage
Get-AppxPackage *zunevideo* | Remove-AppxPackage
Get-AppxPackage *Maps* | Remove-AppxPackage
Get-AppxPackage *solitairecollection* | Remove-AppxPackage
Get-AppxPackage *onenote* | Remove-AppxPackage
Get-AppxPackage *windowsphone* | Remove-AppxPackage
Get-AppxPackage *commsphone* | Remove-AppxPackage
Get-AppxPackage *xboxapp* | Remove-AppxPackage
Get-AppxPackage *sway* | Remove-AppxPackage
Get-AppxPackage *messaging* | Remove-AppxPackage
Get-AppxPackage *ConnectivityStore* | Remove-AppxPackage
Get-AppxPackage *Twitter* | Remove-AppxPackage
Get-AppxPackage *Netflix* | Remove-AppxPackage
Get-AppxPackage *WindowsFeedbackHub* | Remove-AppxPackage
Get-AppxPackage *CandyCrushSodaSaga* | Remove-AppxPackage
Get-AppxPackage *FarmVille2CountryEscape* | Remove-AppxPackage
Get-AppxPackage *Asphalt8Airborne* | Remove-AppxPackage
Get-AppxPackage *Flipboard* | Remove-AppxPackage
Get-AppxPackage *AppConnector* | Remove-AppxPackage
Get-AppxPackage *MicrosoftMahjong* | Remove-AppxPackage
Get-AppxPackage *Mahjong* | Remove-AppxPackage
Get-AppxPackage *Sudoku* | Remove-AppxPackage
Get-AppxPackage *NYTCrossword* | Remove-AppxPackage
Get-AppxPackage *Adobe* | Remove-AppxPackage
Get-AppxPackage *Eclipse* | Remove-AppxPackage
Get-AppxPackage *Pandora* | Remove-AppxPackage
Get-AppxPackage *Finance*
Get-AppxPackage *Power* | Remove-AppxPackage
Get-AppxPackage *Network* | Remove-AppxPackage
Get-AppxPackage  microsoft.windowscommunicationsapps | Remove-AppxPackage
Get-AppxPackage *actipro* | Remove-AppxPackage
