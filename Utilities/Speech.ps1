Add-Type -AssemblyName System.speech
$username = get-aduser $env:username | fl Givenname | out-string
$modusername = $username.replace("Givenname : ","")
$speak = New-Object System.Speech.Synthesis.SpeechSynthesizer
$speak.Speak('Hello'+ $modusername)