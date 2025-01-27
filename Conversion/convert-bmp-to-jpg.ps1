$bmpsource="$env:appdata\Brewpoint\Temp\"
[Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms");
GCI $bmpsource | where-object {$_.Extension -eq “.bmp”}| %{
$file = new-object System.Drawing.Bitmap($_.FullName);
$file.Save($_.Directory.FullName +”\”+ $_.BaseName+”.jpg”,”jpeg”);
$file.Dispose()
}
GCI $bmpsource | where-object {$_.Extension -eq “.bmp”} | Remove-Item -Force