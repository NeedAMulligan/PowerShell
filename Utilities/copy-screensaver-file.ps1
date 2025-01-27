$file = "\\file\path\screensaver.scr"
$destination = "$env:windir\web\screen"
$exclude = Get-ChildItem -recurse $destination
Copy-Item -Recurse $file $destination -Verbose -Exclude $exclude