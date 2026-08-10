# Security policy

## Secret handling

This repository must not contain:

- API keys, OAuth tokens, cookies, passwords, private keys, or account exports;
- local Pi/Grok configuration files (`auth.json`, session logs);
- private hostnames, server addresses, or personal filesystem paths.

Run `scripts/secret-scan.sh` before every public push.

## Reporting

Use GitHub's private security-advisory flow for suspected credential exposure.
Do not paste live credentials into a public issue.
