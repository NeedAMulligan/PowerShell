# Source Directories
$bpath = "$env:Appdata\Brewpoint\"
$bsource = "$env:SystemDrive\Brewpoint"
$apath = "$env:Appdata\Auto-Shopkeeper\"
$asource = "$env:SystemDrive\Auto-ShopKeeper"
$btemppath = "$bpath\Temp"
$atemppath = "$apath\Temp"

# Create Brewpoint folder in local users home folder if not present

If(!(test-path $bpath))
{
      New-Item -ItemType Directory -Force -Path $bpath
}

# Clean up Brewpoint Folder and copy runtime file from source

      Remove-Item -Force $bpath\*.*
      Copy-Item $bsource\BrewpointApp.accdr -destination $bpath -Recurse -Force
      
# Create Brewpoint Temp directory if not present

If(!(test-path $btemppath))
{
      New-Item -ItemType Directory -Force -Path $btemppath
}

# Create Brewpoint folder in local users home folder if not present

If(!(test-path $apath))
{
      New-Item -ItemType Directory -Force -Path $apath
}

# Clean up Brewpoint Folder and copy runtime file from source

      Remove-Item -Force $apath\*.*
      Copy-Item $asource\Auto-ShopKeeper.accdr -destination $apath -Recurse -Force

# Create Brewpoint Temp directory if not present

If(!(test-path $atemppath))
{
      New-Item -ItemType Directory -Force -Path $atemppath
}