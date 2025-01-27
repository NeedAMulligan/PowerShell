systeminfo | find "System Boot Time"

#OR

(get-date) - (gcim Win32_OperatingSystem).LastBootUpTime