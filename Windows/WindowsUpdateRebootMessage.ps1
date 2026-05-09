Add-Type -AssemblyName PresentationCore,PresentationFramework
$ButtonType = [System.Windows.MessageBoxButton]::OK
$MessageboxTitle = “From Rees Broome IT Dept”
$Messageboxbody = “Microsoft Windows Updates have been applied and your computer needs to be restarted to finish installing them. Please restart your computer ASAP. 

This message will repeat every 6 hours until your system has been restarted.

Thanks”
$MessageIcon = [System.Windows.MessageBoxImage]::Warning
[System.Windows.MessageBox]::Show($Messageboxbody,$MessageboxTitle,$ButtonType,$messageicon)