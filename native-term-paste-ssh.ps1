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
$script:ConfigPath = Join-Path $script:InstallDir 'config.json'
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

function Read-RemoteHost {
    $value = Read-Host 'SSH host or alias from ~/.ssh/config (for example: adclaude)'
    $value = $value.Trim()
    if ($value -notmatch '^[A-Za-z0-9_.@-]+$') {
        throw 'Use one SSH host or alias containing only letters, digits, dot, underscore, at sign, or hyphen.'
    }
    return $value
}

function Test-SshTarget([string]$HostName) {
    $sshPath = Find-OpenSsh 'ssh'
    Write-Host "Checking key-based SSH access and /tmp write access on $HostName ..."
    & $sshPath -o BatchMode=yes $HostName 'test -w /tmp'
    if ($LASTEXITCODE -ne 0) {
        throw "SSH check failed. Confirm ssh $HostName works without a password prompt and the account can write to /tmp."
    }
}

function Start-BackgroundWatcher {
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $quotedPath = '"' + $script:RuntimePath.Replace('"', '\"') + '"'
    $arguments = '-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ' + $quotedPath + ' -Watch'
    Start-Process -FilePath $powershellExe -ArgumentList $arguments -WindowStyle Hidden | Out-Null
}

function Install-Tool {
    $hostName = Read-RemoteHost
    $null = Find-OpenSsh 'ssh'
    $null = Find-OpenSsh 'scp'
    Test-SshTarget $hostName

    [System.IO.Directory]::CreateDirectory($script:InstallDir) | Out-Null
    if (-not $PSCommandPath -or -not (Test-Path -LiteralPath $PSCommandPath)) {
        throw 'Run install.ps1 from the repository or use the documented one-line installer. The runtime script must be available beside it.'
    }
    Copy-Item -LiteralPath $PSCommandPath -Destination $script:RuntimePath -Force
    @{ Host = $hostName } | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8

    $runCommand = '"{0}" -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -Watch' -f $powershellExe, $script:RuntimePath
    if (-not (Test-Path -LiteralPath $script:RunKeyPath)) { New-Item -Path $script:RunKeyPath -Force | Out-Null }
    Set-ItemProperty -LiteralPath $script:RunKeyPath -Name $script:RunValueName -Value $runCommand
    Start-BackgroundWatcher

    Write-Host ''
    Write-Host 'Installed. The background hotkey starts at Windows sign-in.'
    Write-Host 'In any terminal client connected to this SSH host, focus the CLI and press Ctrl+Alt+V with an image on the Windows clipboard.'
    Write-Host ('Log: ' + $script:LogPath)
}

function Configure-Tool {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { throw 'Not installed yet. Run install.ps1 first.' }
    $hostName = Read-RemoteHost
    Test-SshTarget $hostName
    @{ Host = $hostName } | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
    Write-Host "Saved $hostName. The running watcher reads the selected host for each paste."
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
    Remove-ItemProperty -LiteralPath $script:RunKeyPath -Name $script:RunValueName -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Removed the sign-in launcher and installed files.'
}

function Start-Watcher {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { throw 'No configuration found; install the tool first.' }
    $config = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json
    if ($config.Host -notmatch '^[A-Za-z0-9_.@-]+$') { throw 'The configured SSH host is invalid.' }

    Add-Type -AssemblyName System.Windows.Forms
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
}
'@ -ErrorAction Stop

    $hotkeyId = 0x4E54
    if (-not [NativeTermPasteWin32]::RegisterHotKey([IntPtr]::Zero, $hotkeyId, 0x0001 -bor 0x0002, 0x56)) {
        Write-Log 'Ctrl+Alt+V is already registered by another process. Watcher exiting.'
        return
    }
    Set-Content -LiteralPath $script:PidPath -Value $PID -Encoding ASCII
    Write-Log ('Watcher ready for SSH host {0}.' -f $config.Host)
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
                $id = [guid]::NewGuid().ToString('N')
                $localFile = Join-Path $env:TEMP ('native-term-paste-' + $id + '.png')
                $remotePath = '/tmp/native-term-paste-' + $id + '.png'
                $image = [System.Windows.Forms.Clipboard]::GetImage()
                try { $image.Save($localFile, [System.Drawing.Imaging.ImageFormat]::Png) }
                finally { $image.Dispose() }

                $scpPath = Find-OpenSsh 'scp'
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $scpPath
                $psi.Arguments = '-q -o BatchMode=yes "{0}" "{1}:{2}"' -f $localFile, $config.Host, $remotePath
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $process = [System.Diagnostics.Process]::Start($psi)
                $process.WaitForExit()
                if ($process.ExitCode -ne 0) { throw "SCP failed with exit code $($process.ExitCode)." }

                [System.Windows.Forms.Clipboard]::SetText($remotePath)
                Start-Sleep -Milliseconds 125
                [System.Windows.Forms.SendKeys]::SendWait('^v')
                Write-Log ('Uploaded image to {0}:{1} and pasted the remote path.' -f $config.Host, $remotePath)
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
