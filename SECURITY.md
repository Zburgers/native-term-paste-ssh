# Security policy

## Supported versions

Security fixes are made on the default branch. Use the latest installer and script from this repository.

## Reporting a vulnerability

Please report suspected vulnerabilities privately through GitHub's **Report a vulnerability** feature for this repository. Do not include clipboard images, SSH keys, passwords, or other secrets in public issues.

## Data handling

The helper does not transmit clipboard data until the user presses the hotkey. It transfers the resulting PNG only to the SSH destination tagged on the focused terminal session, using the user's OpenSSH client and configuration. It does not send telemetry. Logs contain transfer status, host name, and remote path, not image bytes.
