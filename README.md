# Native Terminal Paste over SSH

Paste an image from the Windows clipboard into a command-line AI session running on a remote SSH server, even when the CLI's native image-paste integration cannot access the Windows clipboard.

The Windows helper saves the clipboard image as PNG, identifies the SSH destination belonging to the focused terminal session, copies the image to that server's `/tmp` with OpenSSH `scp`, replaces the local clipboard with the remote path, and sends an ordinary Ctrl+V to the terminal. The CLI receives text such as `/tmp/native-term-paste-<id>.png` instead of an image clipboard event.

## One-time install

Requirements:

- Windows 10 or 11.
- Windows PowerShell 5.1 or PowerShell 7. The background helper itself always runs in the built-in Windows PowerShell 5.1 host, so it does not depend on the PowerShell version used for your terminal or CLI.
- Windows OpenSSH Client (`ssh.exe` and `scp.exe`).
- Key-based SSH access to the remote host, with write permission to `/tmp`.

Open a PowerShell window and run:

```powershell
irm https://raw.githubusercontent.com/Zburgers/native-term-paste-ssh/main/install.ps1 | iex
```

The installer adds a small `ssh` wrapper to the current user's Windows PowerShell 5.1 and PowerShell 7 profiles, installs the background hotkey helper, and starts it automatically at sign-in. Open a **new** PowerShell terminal after installation. No server address is configured or baked into the tool.

## Use

1. Copy an image using any Windows application.
2. Connect to any server from PowerShell with `ssh alias`, `ssh user@host`, or `ssh 192.168.29.14`, then focus the CLI in that session.
3. Press **Ctrl+Alt+V**.
4. The remote path is pasted as text. Submit your prompt when ready.

Ctrl+V remains unchanged for ordinary text paste. A success sound confirms the image was transferred and the path was pasted. An error sound indicates failure. Logs are stored at `%LOCALAPPDATA%\NativeTermPasteSSH\native-term-paste-ssh.log`.

## Compatibility and limits

- **CLI agnostic:** the helper does not call Codex, Claude, or any CLI API. It works with any CLI that accepts a file path in its prompt.
- **Any SSH destination, including IP addresses:** the PowerShell `ssh` wrapper tags each terminal's title with that session's destination. The helper reads the selected Windows Terminal tab title or the foreground console title, so simultaneous SSH sessions can use different servers. No per-host setup or server-side install is needed.
- Use `ssh` from PowerShell so the wrapper can tag the session; typing `ssh.exe` directly bypasses that tag. After install, open a new PowerShell session and reconnect. The foreground terminal must expose its title to Windows; when the helper cannot identify the active destination, it fails safely and does not upload to a stale host.
- The hotkey works independently of the terminal product, but active-session detection depends on that terminal exposing the title set by PowerShell. Terminals that hide or replace console titles cannot be auto-routed safely.
- The file remains on the remote server in `/tmp` according to that server's cleanup policy. The local temporary copy is removed after transfer.
- The image replaces the Windows clipboard with its remote path after a successful transfer.
- Clipboard contents and image bytes are sent only to the SSH host identified for the focused terminal session.
- The helper assumes SSH key authentication is already set up. It uses batch mode so it will not hang on an inaccessible password prompt.
- `Ctrl+Alt+V` must be available as a global hotkey. If another application has claimed it, close that application or change the hotkey constants in the script before installing.

This cannot make an arbitrary CLI understand an image if that CLI does not load image files referenced by path. It solves the Windows-to-remote file transfer and terminal-paste boundary.

## Repair or uninstall

Repair or reinstall the PowerShell session integration:

```powershell
& "$env:LOCALAPPDATA\NativeTermPasteSSH\native-term-paste-ssh.ps1" -Configure
```

Uninstall (removes the sign-in launcher and installed files):

```powershell
& "$env:LOCALAPPDATA\NativeTermPasteSSH\native-term-paste-ssh.ps1" -Uninstall
```

## Security

The helper handles clipboard image data only after the hotkey is pressed. It writes one uniquely named image file to the selected server's `/tmp` directory via the current user's SSH configuration and keys. Do not configure an untrusted host. See [SECURITY.md](SECURITY.md) for reporting security issues.

## License

MIT. See [LICENSE](LICENSE).
