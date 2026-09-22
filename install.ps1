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

foreach ($tool in @('ssh.exe', 'scp.exe')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Cannot find $tool. Enable the Windows OpenSSH Client optional feature, then rerun this installer."
    }
}

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri "$repoRaw/$runtimeName" -OutFile $installScriptPath
Copy-Item -LiteralPath $installScriptPath -Destination $runtimePath -Force
Remove-Item -LiteralPath $installScriptPath -Force -ErrorAction SilentlyContinue
& $runtimePath -Install
