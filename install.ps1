# One-time bootstrapper for Windows PowerShell 5.1 and PowerShell 7.
$ErrorActionPreference = 'Stop'
$repoRaw = 'https://raw.githubusercontent.com/Zburgers/native-term-paste-ssh/main'
$runtimeName = 'native-term-paste-ssh.ps1'
$installDir = Join-Path $env:LOCALAPPDATA 'NativeTermPasteSSH'
$runtimePath = Join-Path $installDir $runtimeName
$installScriptPath = Join-Path $env:TEMP 'native-term-paste-ssh-runtime.ps1'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

$hostName = (Read-Host 'SSH host or alias from ~/.ssh/config (example: adclaude)').Trim()
if ($hostName -notmatch '^[A-Za-z0-9_.@-]+$') {
    throw 'Use one SSH host or alias containing only letters, digits, dot, underscore, at sign, or hyphen.'
}

foreach ($tool in @('ssh.exe', 'scp.exe')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Cannot find $tool. Enable the Windows OpenSSH Client optional feature, then rerun this installer."
    }
}

Write-Host "Checking SSH access and /tmp write access on $hostName ..."
& ssh.exe -o BatchMode=yes $hostName 'test -w /tmp'
if ($LASTEXITCODE -ne 0) { throw 'SSH validation failed. Make sure key-based ssh access works without a password prompt and retry.' }

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri "$repoRaw/$runtimeName" -OutFile $installScriptPath
Copy-Item -LiteralPath $installScriptPath -Destination $runtimePath -Force
Remove-Item -LiteralPath $installScriptPath -Force -ErrorAction SilentlyContinue
@{ Host = $hostName } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $installDir 'config.json') -Encoding UTF8

$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$runCommand = '"{0}" -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -Watch' -f $powershellExe, $runtimePath
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (-not (Test-Path -LiteralPath $runKey)) { New-Item -Path $runKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $runKey -Name 'NativeTermPasteSSH' -Value $runCommand
Start-Process -FilePath $powershellExe -ArgumentList ('-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Watch' -f $runtimePath) -WindowStyle Hidden

Write-Host ''
Write-Host 'Native Terminal Paste over SSH is installed and starts at Windows sign-in.'
Write-Host 'Focus a CLI in a terminal connected to the configured SSH host and press Ctrl+Alt+V after copying an image.'
Write-Host "Log: $installDir\native-term-paste-ssh.log"
