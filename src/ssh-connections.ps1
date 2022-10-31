
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
    [int] $TitleLen
    [string] $Group
    [string] $User
    [string] $_Host
    [string] $Port
    [string] $keyPath
    [System.Array] $_Env
    
    SSHRecord([string] $Title, [string] $User, [string] $Group, [string] $_Host, [string] $Port, [string] $keyPath, [System.Array] $_Env) {
        $this.Title = $Title
        $this.User = $User
        $this.Group = $Group
        $this._Host = $_Host
        $this.Port = $Port
        $this.keyPath = $keyPath
        $this._Env = $_Env
        $this.TitleLen = $Title.Length
    }
}

class ConfMeta {
    [string] $Title
    [int] $MaxMenuWidth
    [int] $MaxGroupWidth

    ConfMeta([string] $Title, [int]$MaxMenuWidth, [int]$MaxGroupWidth) {
        $this.Title = $Title
        $this.MaxMenuWidth = $MaxMenuWidth
        $this.MaxGroupWidth = $MaxGroupWidth
    }
}

function loadConfig([string] $scriptPath) {
    $_path = [string]::Format("{0}/{1}.xml", $scriptPath, $cfgName)
    $xml = [xml](Get-Content -Path $_path)
    $cfg = [ordered]@{}
    $index = 0
    $_max_menu_len = 0
    $_max_group_len = 0
    foreach ($record in $xml.SSHRecords.record) {
        $vars = [System.Collections.ArrayList]@()
        foreach($_env in $record.env) {
            [void]$vars.Add([EnvVar]::new($_env.name, $_env.value))
        }
        $cfg[$index.ToString()] = [SSHRecord]::new($record.title, $record.user, $record.group, $record._host, $record.port, $record.keyPath, $vars)
        $index++
        if ($record.title.length -gt $_max_menu_len) { $_max_menu_len = $record.title.length }
        if ($record.group.length -gt $_max_group_len){ $_max_group_len = $record.group.length}
    }
    return [ConfMeta]::new($xml.SSHRecords.title, $_max_menu_len, $_max_group_len), $cfg
}

function moveCursor{ param($position)
    $host.UI.RawUI.CursorPosition = $position
}

function RedrawMenuItems{ 
    param ([SSHRecord[]]$menuItems, [ConfMeta]$meta, $oldMenuPos=0, $menuPosition=0, $currPos)
    
    # +1 comes from leading new line in the menu
    $menuLen = $menuItems.Count + 1
    $fcolor = $host.UI.RawUI.ForegroundColor
    $bcolor = $host.UI.RawUI.BackgroundColor
    $gcolor = "DarkGray"
    
    $menuOldPos = New-Object System.Management.Automation.Host.Coordinates(0, ($currPos.Y - ($menuLen - $oldMenuPos)))
    $menuNewPos = New-Object System.Management.Automation.Host.Coordinates(0, ($currPos.Y - ($menuLen - $menuPosition)))
    
    $_spacer_old = $(" " * ($meta.MaxMenuWidth - $menuItems[$oldMenuPos].TitleLen))
    $_spacer = $(" " * ($meta.MaxMenuWidth - $menuItems[$menuPosition].TitleLen))

    moveCursor $menuOldPos
    Write-Host "`t" -NoNewLine
    Write-Host "$oldMenuPos. $($menuItems[$oldMenuPos].Title)" -fore $fcolor -back $bcolor -NoNewLine
    if ($menuItems[$oldMenuPos].Group.length -ne 0) {
        Write-Host "$($_spacer_old) [$($menuItems[$oldMenuPos].Group)]" -fore $gcolor -back $bcolor -NoNewLine
    }

    moveCursor $menuNewPos
    Write-Host "`t" -NoNewLine
    Write-Host "$menuPosition. $($menuItems[$menuPosition].Title)" -fore $bcolor -back $fcolor -NoNewLine
    if ($menuItems[$menuPosition].Group.length -ne 0) {
        Write-Host "$($_spacer) [$($menuItems[$menuPosition].Group)]" -fore $gcolor -back $bcolor -NoNewLine
    }

    moveCursor $currPos
}

function DrawMenu { param ([SSHRecord[]]$menuItems, [ConfMeta] $meta, $menuPosition, $menuTitel)
    $fcolor = $host.UI.RawUI.ForegroundColor
    $bcolor = $host.UI.RawUI.BackgroundColor
    $gcolor = "DarkGray"

    $menuwidth = $menuTitel.length + 4
    Write-Host "`t" -NoNewLine;    Write-Host ("=" * $menuwidth) -fore $fcolor -back $bcolor
    Write-Host "`t" -NoNewLine;    Write-Host " $menuTitel " -fore $fcolor -back $bcolor
    Write-Host "`t" -NoNewLine;    Write-Host ("=" * $menuwidth) -fore $fcolor -back $bcolor
    Write-Host ""
    for ($i = 0; $i -le $menuItems.length;$i++) {
        $_spacer = $(" " * ($meta.MaxMenuWidth - $menuItems[$i].TitleLen))
        Write-Host "`t" -NoNewLine
        if ($i -eq $menuPosition) {
            Write-Host "$i. $($menuItems[$i].Title)" -fore $bcolor -back $fcolor -NoNewline
            if ($menuItems[$i].Group.length -ne 0) {
                Write-Host "$($_spacer) [$($menuItems[$i].Group)]" -fore $gcolor -back $bcolor -NoNewline
            }
            Write-Host "" -fore $fcolor -back $bcolor
        } else {
            if ($($menuItems[$i])) {
                Write-Host "$i. $($menuItems[$i].Title)" -fore $fcolor -back $bcolor -NoNewline
                if ($menuItems[$i].Group.length -ne 0) {
                    Write-Host "$($_spacer) [$($menuItems[$i].Group)]" -fore $gcolor -back $bcolor
                } else {
                    Write-Host ""
                }
            } 
        }
    }
    # leading new line
    Write-Host ""
}

function Menu { param ([SSHRecord[]]$menuItems, [ConfMeta] $meta, $menuTitle = "MENU")
    $vkeycode = 0
    $pos = 0
    $oldPos = 0
    DrawMenu $menuItems $meta $pos $menuTitle
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
        RedrawMenuItems $menuItems $meta $oldPos $pos $currPos
    }
    Write-Output $pos
}

$meta, $cfg = loadConfig($scriptPath)
$records = $cfg.values -as [SSHRecord[]]
$selection = Menu $records $meta ([string]::Format("Select {0} server to login", $meta.title))
[SSHRecord]$record = $cfg[$selection]

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