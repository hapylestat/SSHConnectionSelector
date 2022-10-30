using System;


// cmd.exe: %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /t:exe /out:pass.exe pass.cs
// ps     : & $env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe /t:exe /out:pass.exe pass.cs

namespace SSHPasswordProvider {
 class Program  { 
  static void Main(string[] args) {

    var value = System.Environment.GetEnvironmentVariable("SSH_KEY_PASS");
    Console.Write(value);
  }
 }
}