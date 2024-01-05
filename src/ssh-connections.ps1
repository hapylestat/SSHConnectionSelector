#!/usr/bin/env powershell

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$cfgName = [io.path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)


class Colors {
    static [string] $fontColor = $host.UI.RawUI.ForegroundColor
    static [string] $backColor = $host.UI.RawUI.BackgroundColor
    static [string] $groupColor = "Magenta"   
    static [string] $notOnlineColor = "Red"
}

class EnvVar {
    [string] $Name; [string] $Value

    EnvVar([string]$Name, [string]$Value) {
        $this.Name, $this.Value = $Name, $Value
    }

    static [EnvVar[]] parse([Array] $env) {
        $vars = [System.Collections.ArrayList]@()
        foreach($_env in $env) {
            [void]$vars.Add([EnvVar]::new($_env.name, $_env.value))
        }
        return $vars
    }

    static [void] setVars([EnvVar[]] $variables) {
        foreach($var in $variables) {
            $_name = $var.Name
            if (Test-Path env:$_name) {
                Remove-Item env:$_name | out-null
            }
            New-Item env:$_name -Value $var.Value | out-null
        }
    }

    static [void] clearVars([EnvVar[]] $variables) {
        foreach($var in $variables) {
            $_name = $var.Name
            if (Test-Path env:$_name) {
                Remove-Item env:$_name | out-null
            }
        }
    }
}

class SSHRecord {
    [string] $Title; [string] $Group; [string] $User; [string] $_Host; [string] $Port; [string] $keyPath
    [int] $TitleLen
    [System.Array] $_Env

    hidden [bool] $__isReachable = $null
    hidden [bool] $__J1_received = $false
    hidden [object] $isReachableAsync = $null
    
    SSHRecord([string] $Title, [string] $User, [string] $Group, [string] $_Host, [string] $Port, [string] $keyPath, [System.Array] $_Env) {
        $this.Title, $this.User, $this.Group, $this._Host, $this.Port, $this.keyPath, $this._Env =
            $Title, $User, $Group, $_Host, $Port, $keyPath, $_Env
        $this.TitleLen = $Title.Length
        
        $this.isReachableAsync = Start-Job -ScriptBlock {
            Test-Connection -ComputerName $args[0] -TimeoutSeconds 1 -Count 1
        }  -ArgumentList $_Host
    }

    [bool] GetIsReachable(){
        if (! $this.__J1_received) {
            $job = Receive-Job $this.isReachableAsync -Wait -AutoRemoveJob
            $this.__isReachable = $job[$job.Length-1].Status -eq  [System.Net.NetworkInformation.IPStatus]::Success
            $this.__J1_received = $true
        }
        return $this.__isReachable
    }
    
    [System.Collections.ArrayList] buildArgs(){
        $ssh_args = [System.Collections.ArrayList]@()
        $os = $env:os
        if ($os -eq "Windows_NT") {
         [void]$ssh_args.AddRange(@("-o", "UserKnownHostsFile=NUL"))
        } else {
          [void]$ssh_args.AddRange(@("-o", "UserKnownHostsFile=/dev/null"))
        }
        
        
        [void]$ssh_args.AddRange(@("-o", "StrictHostKeyChecking=no", $this._Host))       
        
        if ($this.Port -ne "") { [void]$ssh_args.AddRange(@("-p", $this.Port)) }
        if ($this.User -ne "") { [void]$ssh_args.AddRange(@("-l", $this.User)) }
        if ($this.keyPath -ne "") { [void]$ssh_args.AddRange(@("-i", $this.keyPath)) }

        return $ssh_args
    }
}

class Conf {
    [string] $Title
    [int] $MaxMenuWidth; [int] $MaxGroupWidth
    [SSHRecord[]] $Records

    Conf([string] $Title, [int]$MaxMenuWidth, [int]$MaxGroupWidth, [SSHRecord[]] $records) {
        $this.Title = $Title
        $this.MaxMenuWidth, $this.MaxGroupWidth = $MaxMenuWidth, $MaxGroupWidth
        $this.Records = $records
    }

    static [Conf] parse([string] $Title, [Array] $records) {
        $sshRecords = [System.Collections.ArrayList]@()
        $counters = @(0, 0)  # index, menu_len, group_len
        foreach ($record in $records) {
            $sshRecords.Add([SSHRecord]::new($record.title, $record.user, $record.group, $record._host, $record.port, $record.keyPath, [EnvVar]::parse($record.env)))
            if ($record.title.length -gt $counters[0]++) { $counters[0] = $record.title.length }
            if ($record.group.length -gt $counters[1]++){ $counters[1] = $record.group.length}
        }
        return [Conf]::new($Title, $counters[0], $counters[1], $sshRecords)
    }
}

function loadConfig([string] $scriptPath) {
    $xml = [xml](Get-Content -Path $([string]::Format("{0}/{1}.xml", $scriptPath, $cfgName)))       
    return [Conf]::parse($xml.SSHRecords.title, $xml.SSHRecords.record)
}

function moveCursor{ param($position)
    $host.UI.RawUI.CursorPosition = $position
}

function RedrawMenuItems{ 
    param ([Conf]$cfg, $oldMenuPos=0, $menuPosition=0, $currPos)

    $menuItems = $cfg.Records
    # +1 comes from leading new line in the menu
    $menuLen = $menuItems.Count + 1   
    $menuOldPos = New-Object System.Management.Automation.Host.Coordinates(0, ($currPos.Y - ($menuLen - $oldMenuPos)))
    $menuNewPos = New-Object System.Management.Automation.Host.Coordinates(0, ($currPos.Y - ($menuLen - $menuPosition)))
    
    $_spacer_old = $(" " * ($cfg.MaxMenuWidth - $menuItems[$oldMenuPos].TitleLen))
    $_spacer = $(" " * ($cfg.MaxMenuWidth - $menuItems[$menuPosition].TitleLen))

    moveCursor $menuOldPos
    Write-Host "`t" -NoNewLine
    Write-Host "$oldMenuPos. $($menuItems[$oldMenuPos].Title)" -fore $($menuItems[$oldMenuPos].GetIsReachable() ? [Colors]::fontColor : [Colors]::notOnlineColor) -back $([Colors]::backColor) -NoNewLine
    if ($menuItems[$oldMenuPos].Group.length -ne 0) {
        Write-Host "$($_spacer_old) [$($menuItems[$oldMenuPos].Group)]" -fore $([Colors]::groupColor) -back $([Colors]::backColor) -NoNewLine
    }

    moveCursor $menuNewPos
    Write-Host "`t" -NoNewLine
    Write-Host "$menuPosition. $($menuItems[$menuPosition].Title)" -fore $([Colors]::backColor) -back $($menuItems[$menuPosition].GetIsReachable() ? [Colors]::fontColor : [Colors]::notOnlineColor) -NoNewLine
    if ($menuItems[$menuPosition].Group.length -ne 0) {
        Write-Host "$($_spacer) [$($menuItems[$menuPosition].Group)]" -fore $([Colors]::groupColor) -back $([Colors]::backColor) -NoNewLine
    }

    moveCursor $currPos
}

function DrawMenu { param ([Conf] $cfg, $menuPosition, $menuTitle)
    $menuItems = $cfg.Records
    $menuwidth = $menuTitle.length + 4
    Write-Host "`t" -NoNewLine;    Write-Host ("=" * $menuwidth) -fore $([Colors]::fontColor) -back $([Colors]::backColor)
    Write-Host "`t" -NoNewLine;    Write-Host " $menuTitle " -fore $([Colors]::fontColor) -back $([Colors]::backColor)
    Write-Host "`t" -NoNewLine;    Write-Host ("=" * $menuwidth) -fore $([Colors]::fontColor) -back $([Colors]::backColor)
    Write-Host ""
    for ($i = 0;$i -le $menuItems.length;$i++) {
        $menuItem = $menuItems[$i]
        $_spacer = $(" " * ($cfg.MaxMenuWidth - $menuItem.TitleLen))
        Write-Host "`t" -NoNewLine
        if ($i -eq $menuPosition) {
            Write-Host "$i. $($menuItem.Title)" -fore $( $menuItem.GetIsReachable() ? [Colors]::backColor : [Colors]::notOnlineColor) -back $([Colors]::fontColor) -NoNewline
            if ($menuItem.Group.length -ne 0) {
                Write-Host "$($_spacer) [$($menuItem.Group)]" -fore $([Colors]::groupColor) -back $([Colors]::backColor) -NoNewline
            }
            Write-Host "" -fore $([Colors]::fontColor) -back $([Colors]::backColor)
        } else {
            if ($($menuItem)) {
                Write-Host "$i. $($menuItem.Title)" -fore $($menuItem.GetIsReachable() ? [Colors]::fontColor : [Colors]::notOnlineColor) -back $([Colors]::backColor) -NoNewline
                if ($menuItem.Group.length -ne 0) {
                    Write-Host "$($_spacer) [$($menuItem.Group)]" -fore $([Colors]::groupColor) -back $([Colors]::backColor)
                } else {
                    Write-Host ""
                }
            } 
        }
    }
    # leading new line
    Write-Host ""
}

function Menu { param ([Conf] $cfg, $menuTitle = "MENU")
    $vkeycode = 0; $pos = 0; $oldPos = 0
    $menuItems = $cfg.Records
    DrawMenu $cfg $pos $menuTitle
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
        RedrawMenuItems $cfg $oldPos $pos $currPos
    }
    Write-Output $pos
}

$cfg = loadConfig($scriptPath)
Start-Sleep -Seconds 1 
[SSHRecord]$record = $cfg.Records[$(Menu $cfg ([string]::Format("Select {0} server to login", $cfg.title)))]

[EnvVar]::setVars($record._Env)
& ssh $record.buildArgs()
[EnvVar]::clearVars($record._Env)
