
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$cfgName = [io.path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

class EnvVar {
    [string] $Name
    [string] $Value

    EnvVar([string]$Name, [string]$Value) {
        $this.Name = $Name
        $this.Value = $Value
    }
}

class SSHRecord {
    [string] $Title
    [string] $User
    [string] $_Host
    [string] $Port
    [string] $keyPath
    [System.Array] $_Env
    
    SSHRecord([string] $Title, [string] $User, [string] $_Host, [string] $Port, [string] $keyPath, [System.Array] $_Env) {
        $this.Title = $Title
        $this.User = $User
        $this._Host = $_Host
        $this.Port = $Port
        $this.keyPath = $keyPath
        $this._Env = $_Env
    }
}

function loadConfig([string] $scriptPath) {
    $_path = [string]::Format("{0}/{1}.xml", $scriptPath, $cfgName)
    $xml = [xml](Get-Content -Path $_path)
    $cfg = [ordered]@{}
    $index = 0
    foreach ($record in $xml.SSHRecords.record) {
        $vars = [System.Collections.ArrayList]@()
        foreach($_env in $record.env) {
            [void]$vars.Add([EnvVar]::new($_env.name, $_env.value))
        }
        $cfg[$index.ToString()] = [SSHRecord]::new($record.title, $record.user,$record._host, $record.port, $record.keyPath, $vars)
        $index++
    }
    return $xml.SSHRecords.title, $cfg
}

function moveCursor{ param($position)
    $host.UI.RawUI.CursorPosition = $position
}

function RedrawMenuItems{ 
    param ([array]$menuItems, $oldMenuPos=0, $menuPosition=0, $currPos)
    
    # +1 comes from leading new line in the menu
    $menuLen = $menuItems.Count + 1
    $fcolor = $host.UI.RawUI.ForegroundColor
    $bcolor = $host.UI.RawUI.BackgroundColor
    $menuOldPos = New-Object System.Management.Automation.Host.Coordinates(0, ($currPos.Y - ($menuLen - $oldMenuPos)))
    $menuNewPos = New-Object System.Management.Automation.Host.Coordinates(0, ($currPos.Y - ($menuLen - $menuPosition)))
    
    moveCursor $menuOldPos
    Write-Host "`t" -NoNewLine
    Write-Host "$oldMenuPos. $($menuItems[$oldMenuPos])" -fore $fcolor -back $bcolor -NoNewLine

    moveCursor $menuNewPos
    Write-Host "`t" -NoNewLine
    Write-Host "$menuPosition. $($menuItems[$menuPosition])" -fore $bcolor -back $fcolor -NoNewLine

    moveCursor $currPos
}

function DrawMenu { param ([array]$menuItems, $menuPosition, $menuTitel)
    $fcolor = $host.UI.RawUI.ForegroundColor
    $bcolor = $host.UI.RawUI.BackgroundColor

    $menuwidth = $menuTitel.length + 4
    Write-Host "`t" -NoNewLine;    Write-Host ("=" * $menuwidth) -fore $fcolor -back $bcolor
    Write-Host "`t" -NoNewLine;    Write-Host " $menuTitel " -fore $fcolor -back $bcolor
    Write-Host "`t" -NoNewLine;    Write-Host ("=" * $menuwidth) -fore $fcolor -back $bcolor
    Write-Host ""
    for ($i = 0; $i -le $menuItems.length;$i++) {
        Write-Host "`t" -NoNewLine
        if ($i -eq $menuPosition) {
            Write-Host "$i. $($menuItems[$i])" -fore $bcolor -back $fcolor -NoNewline
            Write-Host "" -fore $fcolor -back $bcolor
        } else {
            if ($($menuItems[$i])) {
                Write-Host "$i. $($menuItems[$i])" -fore $fcolor -back $bcolor
            } 
        }
    }
    # leading new line
    Write-Host ""
}

function Menu { param ([array]$menuItems, $menuTitel = "MENU")
    $vkeycode = 0
    $pos = 0
    $oldPos = 0
    DrawMenu $menuItems $pos $menuTitel
    $currPos=$host.UI.RawUI.CursorPosition
    While ($vkeycode -ne 13) {
        $press = $host.ui.rawui.readkey("NoEcho,IncludeKeyDown")
        $vkeycode = $press.virtualkeycode  # https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
        Write-host "$($press.character)" -NoNewLine
        $oldPos=$pos;

        Switch ($vkeycode) {
            33 {$pos = if ($pos - 2 -gt 0)  {$pos - 2} Else {0}}  #PgUP
            34 {$pos = if ($pos + 2 -lt @($menuItems).length)  {$pos + 2} Else {@($menuItems).length}} #PgDn
            35 {$pos = @($menuItems).length}  # End
            36 {$pos = 0} # Up
            38 {$pos--} # Arrow UP
            40 {$pos++} # Arrow DOWN
        }
        if ($pos -lt 0) {$pos = 0}
        if ($pos -ge $menuItems.length) {$pos = $menuItems.length -1}
        RedrawMenuItems $menuItems $oldPos $pos $currPos
    }
    Write-Output $pos
}

$title, $cfg = loadConfig($scriptPath)
$bad = New-Object string[] $cfg.Keys.Count
foreach($t in $cfg.Keys) { $bad[$t] = $cfg[$t].title}

$selection = Menu $bad ([string]::Format("Select {0} server to login", $title))

[SSHRecord]$record =  $cfg[$selection]

$ssh_args = [System.Collections.ArrayList]@()
[void]$ssh_args.AddRange(@("-o", "StrictHostKeyChecking=no", $record._host))

if ($record.port -ne "") { [void]$ssh_args.AddRange(@("-p", $record.port)) }
if ($record.user -ne "") { [void]$ssh_args.AddRange(@("-l", $record.user)) }
if ($record.keyPath -ne "") { [void]$ssh_args.AddRange(@("-i", $record.keyPath)) }

foreach($var in $record._Env) {
    $_name = $var.Name
    if (Test-Path env:$_name) {
        Remove-Item env:$_name | out-null
    }
    New-Item env:$_name -Value $var.Value | out-null
}

& ssh $ssh_args

foreach($var in $record._Env) {
    $_name = $var.Name
    if (Test-Path env:$_name) {
        Remove-Item env:$_name | out-null
    }
}