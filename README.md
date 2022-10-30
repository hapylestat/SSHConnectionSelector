How to use
------------
- Copy `ssh-connections.ps1` and `ssh-connections.xml` files from the `src` folder locally. Rename files as desired - ps1 and xml files should have same base nane.
- Modify configuration `xml` file, populate connection according to the `normal` samples present in the file. 

Password protected keys
----------------------
It's possible to automate login process for the password-protected keys: 
- build helper app `src/ask-password-helper/pass.cs` by executing `src/pass.cs/build.ps1`. If Fraamework path is incorrect, please adjust to proper one.
- move resulting `pass.exe` file to some trusted place for apps
- set `SSH_ASKPASS` variabme in configuration `xml`, first sample, to the full path of the `pass.exe`
- configure the connection according to the first samle in `xml`



Integrate with Windows Terminal
-------------------------------
- Open Setting
- Open JSON File 
- navigate to profiles\list
- add entry: 
```
            {
                "commandline": "powershell -ExecutionPolicy Bypass -NoProfile -File ssh-connections.ps1",
                "guid": "{random guid}",
                "hidden": false,
                "name": "My SSH Connections List"
            }
```

New guid could be generate by PowerShell command: `New-Guid`