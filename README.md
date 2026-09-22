# Native Terminal Paste over SSH

Paste an image from the Windows clipboard into a command-line AI session running on a remote SSH server, even when the CLI's native image-paste integration cannot access the Windows clipboard.

The Windows helper saves the clipboard image as PNG, copies it to `/tmp` on a configured SSH host with OpenSSH `scp`, replaces the local clipboard with the remote path, and sends an ordinary Ctrl+V to the focused terminal. The CLI receives text such as `/tmp/native-term-paste-<id>.png` instead of an image clipboard event.

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

When prompted, enter the host or alias from your SSH config. The installer checks SSH access, installs a background helper for the current Windows user, starts it immediately, and arranges for it to start automatically at sign-in. No CLI plugin, shell profile edit, server package, or administrator access is required.

## Use

1. Copy an image using any Windows application.
2. Focus the input area of a CLI in a terminal connected to the configured SSH host.
3. Press **Ctrl+Alt+V**.
4. The remote path is pasted as text. Submit your prompt when ready.

Ctrl+V remains unchanged for ordinary text paste. A success sound confirms the image was transferred and the path was pasted. An error sound indicates failure. Logs are stored at `%LOCALAPPDATA%\NativeTermPasteSSH\native-term-paste-ssh.log`.

## Compatibility and limits

- **CLI agnostic:** the helper does not call Codex, Claude, or any CLI API. It works with any CLI that accepts a file path in its prompt.
- **Terminal-client agnostic:** the hotkey is registered with Windows, not with a specific terminal application. The terminal must be the foreground window and accept a normal Ctrl+V paste.
- **SSH-host agnostic:** any host reachable through Windows OpenSSH and writable at `/tmp` can be selected during install. The host is a one-time setting because an SCP transfer must have a destination. To change it later, run the installed script with `-Configure`.
- The file remains on the remote server in `/tmp` according to that server's cleanup policy. The local temporary copy is removed after transfer.
- The image replaces the Windows clipboard with its remote path after a successful transfer.
- Clipboard contents and image bytes are sent only to the configured SSH host.
- The helper assumes SSH key authentication is already set up. It uses batch mode so it will not hang on an inaccessible password prompt.
- `Ctrl+Alt+V` must be available as a global hotkey. If another application has claimed it, close that application or change the hotkey constants in the script before installing.

This cannot make an arbitrary CLI understand an image if that CLI does not load image files referenced by path. It solves the Windows-to-remote file transfer and terminal-paste boundary.

## Change the host or uninstall

Change host:

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
