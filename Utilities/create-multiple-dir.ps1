#[range]..[range] | foreach $_{ New-Item -ItemType directory -Name $("prepend-data" + $_ "append data") }

2011..2023 | foreach $_{ New-Item -ItemType directory -Name $($_) }

