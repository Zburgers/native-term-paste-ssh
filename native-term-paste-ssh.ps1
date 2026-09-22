# Native Terminal Paste over SSH
# Windows PowerShell 5.1 compatible; runs independently of the user's CLI or PowerShell host.
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Uninstall,
    [switch]$Watch
)

$ErrorActionPreference = 'Stop'
$script:AppName = 'NativeTermPasteSSH'
$script:InstallDir = Join-Path $env:LOCALAPPDATA $script:AppName
$script:RuntimePath = Join-Path $script:InstallDir 'native-term-paste-ssh.ps1'
$script:LogPath = Join-Path $script:InstallDir 'native-term-paste-ssh.log'
$script:PidPath = Join-Path $script:InstallDir 'watcher.pid'
$script:RunKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:RunValueName = 'NativeTermPasteSSH'

function Write-Log([string]$Message) {
    [System.IO.Directory]::CreateDirectory($script:InstallDir) | Out-Null
    Add-Content -LiteralPath $script:LogPath -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Find-OpenSsh([string]$Name) {
    $cmd = Get-Command ($Name + '.exe') -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $cmd) { throw "Cannot find $Name.exe. Install the Windows OpenSSH Client optional feature and retry." }
    return $cmd.Source
}

function Get-SshProfileBlock {
    return @'
# >>> NativeTermPasteSSH SSH title integration >>>
function global:ssh {
    $sshCommand = Get-Command ssh.exe -ErrorAction Stop | Select-Object -First 1
    $sshArguments = @($args)
    $takesValue = @('B','b','c','D','E','e','F','I','i','J','L','l','m','O','o','p','Q','R','S','W','w')
    $skipValue = $false
    $destination = $null
    foreach ($argument in $sshArguments) {
        if ($skipValue) { $skipValue = $false; continue }
        if ($argument -eq '--') { continue }
        if ($argument.StartsWith('-')) {
            if ($argument.Length -eq 2 -and $takesValue -contains $argument.Substring(1,1)) { $skipValue = $true }
            continue
        }
        $destination = $argument
        break
    }
    if (-not $destination) { & $sshCommand.Source @sshArguments; return }

    $title = 'NTPSSH:' + $destination
    $oldTitle = ''
    try { $oldTitle = [Console]::Title } catch {}
    $sourceId = 'NativeTermPasteSSH-' + [guid]::NewGuid().ToString('N')
    $timer = New-Object System.Timers.Timer
    $timer.Interval = 350
    $timer.AutoReset = $true
    $null = Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $sourceId -MessageData $title -Action {
        try { [Console]::Title = [string]$Event.MessageData } catch {}
    }
    try {
        try { [Console]::Title = $title } catch {}
        $timer.Start()
        & $sshCommand.Source @sshArguments
        $global:LASTEXITCODE = $LASTEXITCODE
    }
    finally {
        $timer.Stop()
        Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
        Get-Job | Where-Object { $_.Name -eq $sourceId } | Remove-Job -Force -ErrorAction SilentlyContinue
        try { [Console]::Title = $oldTitle } catch {}
        $timer.Dispose()
    }
}
# <<< NativeTermPasteSSH SSH title integration <<<
'@
}

function Set-SshProfileIntegration([switch]$Remove) {
    $block = Get-SshProfileBlock
    $paths = @(
        (Join-Path $HOME 'Documents\WindowsPowerShell\profile.ps1'),
        (Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $HOME 'Documents\PowerShell\profile.ps1'),
        (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1')
    )
    foreach ($profilePath in ($paths | Select-Object -Unique)) {
        $profileDir = Split-Path -Parent $profilePath
        [System.IO.Directory]::CreateDirectory($profileDir) | Out-Null
        $text = if (Test-Path -LiteralPath $profilePath) { Get-Content -LiteralPath $profilePath -Raw } else { '' }
        $pattern = '(?s)\r?\n?# >>> NativeTermPasteSSH SSH title integration >>>.*?# <<< NativeTermPasteSSH SSH title integration <<<\r?\n?'
        $text = [regex]::Replace($text, $pattern, '')
        if (-not $Remove) { $text = $text.TrimEnd() + "`r`n`r`n" + $block + "`r`n" }
        Set-Content -LiteralPath $profilePath -Value $text -Encoding UTF8
    }
    if (-not $Remove) { Invoke-Expression $block }
}

function Start-BackgroundWatcher {
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $quotedPath = '"' + $script:RuntimePath.Replace('"', '\"') + '"'
    $arguments = '-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ' + $quotedPath + ' -Watch'
    Start-Process -FilePath $powershellExe -ArgumentList $arguments -WindowStyle Hidden | Out-Null
}

function Install-Tool {
    $null = Find-OpenSsh 'ssh'
    $null = Find-OpenSsh 'scp'

    [System.IO.Directory]::CreateDirectory($script:InstallDir) | Out-Null
    if (-not $PSCommandPath -or -not (Test-Path -LiteralPath $PSCommandPath)) {
        throw 'Run install.ps1 from the repository or use the documented one-line installer. The runtime script must be available beside it.'
    }
    if ([System.IO.Path]::GetFullPath($PSCommandPath) -ne [System.IO.Path]::GetFullPath($script:RuntimePath)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $script:RuntimePath -Force
    }
    Remove-Item -LiteralPath (Join-Path $script:InstallDir 'config.json') -Force -ErrorAction SilentlyContinue
    Set-SshProfileIntegration

    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $runCommand = '"{0}" -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -Watch' -f $powershellExe, $script:RuntimePath
    if (-not (Test-Path -LiteralPath $script:RunKeyPath)) { New-Item -Path $script:RunKeyPath -Force | Out-Null }
    Set-ItemProperty -LiteralPath $script:RunKeyPath -Name $script:RunValueName -Value $runCommand
    Start-BackgroundWatcher

    Write-Host ''
    Write-Host 'Installed. The background hotkey starts at Windows sign-in.'
    Write-Host 'Open a new PowerShell terminal and connect with `ssh <any-host-or-IP>`. The active SSH destination is detected per terminal session.'
    Write-Host 'Then focus the CLI and press Ctrl+Alt+V with an image on the Windows clipboard.'
    Write-Host ('Log: ' + $script:LogPath)
}

function Configure-Tool {
    Set-SshProfileIntegration
    Write-Host 'Installed SSH title integration for PowerShell 5.1 and PowerShell 7. Open a new terminal session to use automatic host detection.'
}

function Stop-ToolWatcher {
    if (Test-Path -LiteralPath $script:PidPath) {
        $watcherPid = 0
        if ([int]::TryParse((Get-Content -LiteralPath $script:PidPath -Raw).Trim(), [ref]$watcherPid)) {
            Stop-Process -Id $watcherPid -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $script:PidPath -Force -ErrorAction SilentlyContinue
    }
}

function Uninstall-Tool {
    Stop-ToolWatcher
    Set-SshProfileIntegration -Remove
    Remove-ItemProperty -LiteralPath $script:RunKeyPath -Name $script:RunValueName -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Removed the sign-in launcher and installed files.'
}

function Get-ActiveSshDestination {
    $window = [NativeTermPasteWin32]::GetForegroundWindow()
    if ($window -eq [IntPtr]::Zero) { throw 'No foreground terminal window was found.' }
    $title = [NativeTermPasteWin32]::WindowTitle($window)
    [uint32]$ownerPid = 0
    [NativeTermPasteWin32]::GetWindowThreadProcessId($window, [ref]$ownerPid) | Out-Null
    $owner = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue

    # Windows Terminal's top-level HWND belongs to the shared UI process. Read its selected tab title,
    # which the PowerShell ssh wrapper marks with the destination for that particular session.
    if ($owner -and $owner.ProcessName -eq 'WindowsTerminal') {
        try {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($window)
            $condition = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::TabItem
            )
            $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
            foreach ($tab in $tabs) {
                $selection = $null
                if ($tab.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection) -and $selection.Current.IsSelected) {
                    $title = $tab.Current.Name
                    break
                }
            }
        } catch { }
    }

    if ($title -match '(?:^|[| ])NTPSSH:([^\s|]+)(?:$|[| ])') { return $Matches[1] }
    throw 'This terminal session has no detected SSH destination. Connect with the PowerShell ssh command (not ssh.exe) in a new terminal session; no upload was made.'
}

function Start-Watcher {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativeTermPasteWin32 {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x; public int y; }
    [StructLayout(LayoutKind.Sequential)] public struct MSG {
        public IntPtr hwnd; public uint message; public UIntPtr wParam; public IntPtr lParam;
        public uint time; public POINT pt;
    }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] public static extern int GetMessage(out MSG message, IntPtr hWnd, uint min, uint max);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int maxCount);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    public static string WindowTitle(IntPtr hWnd) {
        var text = new System.Text.StringBuilder(1024);
        GetWindowText(hWnd, text, text.Capacity);
        return text.ToString();
    }
}
'@ -ErrorAction Stop

    $hotkeyId = 0x4E54
    if (-not [NativeTermPasteWin32]::RegisterHotKey([IntPtr]::Zero, $hotkeyId, 0x0001 -bor 0x0002, 0x56)) {
        Write-Log 'Ctrl+Alt+V is already registered by another process. Watcher exiting.'
        return
    }
    Set-Content -LiteralPath $script:PidPath -Value $PID -Encoding ASCII
    Write-Log 'Watcher ready; SSH destination will be detected from the foreground terminal session.'
    try {
        while ($true) {
            $message = New-Object NativeTermPasteWin32+MSG
            if ([NativeTermPasteWin32]::GetMessage([ref]$message, [IntPtr]::Zero, 0, 0) -le 0) { break }
            if ($message.message -ne 0x0312 -or [uint32]$message.wParam.ToUInt32() -ne $hotkeyId) { continue }
            $localFile = $null
            try {
                if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) {
                    [System.Media.SystemSounds]::Beep.Play()
                    Write-Log 'Hotkey pressed, but clipboard does not contain an image.'
                    continue
                }
                $destination = Get-ActiveSshDestination
                $id = [guid]::NewGuid().ToString('N')
                $localFile = Join-Path $env:TEMP ('native-term-paste-' + $id + '.png')
                $remotePath = '/tmp/native-term-paste-' + $id + '.png'
                $image = [System.Windows.Forms.Clipboard]::GetImage()
                try { $image.Save($localFile, [System.Drawing.Imaging.ImageFormat]::Png) }
                finally { $image.Dispose() }

                $scpPath = Find-OpenSsh 'scp'
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $scpPath
                $psi.Arguments = '-q -o BatchMode=yes "{0}" "{1}:{2}"' -f $localFile, $destination, $remotePath
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $process = [System.Diagnostics.Process]::Start($psi)
                $process.WaitForExit()
                if ($process.ExitCode -ne 0) { throw "SCP failed with exit code $($process.ExitCode)." }

                [System.Windows.Forms.Clipboard]::SetText($remotePath)
                Start-Sleep -Milliseconds 125
                [System.Windows.Forms.SendKeys]::SendWait('^v')
                Write-Log ('Uploaded image to {0}:{1} and pasted the remote path.' -f $destination, $remotePath)
                [System.Media.SystemSounds]::Asterisk.Play()
            }
            catch {
                Write-Log ('Paste failed: ' + $_.Exception.Message)
                [System.Media.SystemSounds]::Hand.Play()
            }
            finally {
                if ($localFile -and (Test-Path -LiteralPath $localFile)) { Remove-Item -LiteralPath $localFile -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    finally {
        [NativeTermPasteWin32]::UnregisterHotKey([IntPtr]::Zero, $hotkeyId) | Out-Null
        Remove-Item -LiteralPath $script:PidPath -Force -ErrorAction SilentlyContinue
    }
}

if ($Install) { Install-Tool; exit }
if ($Configure) { Configure-Tool; exit }
if ($Uninstall) { Uninstall-Tool; exit }
if ($Watch) { Start-Watcher; exit }
