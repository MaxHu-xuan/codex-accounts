# Security policy

## Scope

This project is a local macOS account and quota viewer for Codex. It stores
each account's cached login state in a separate macOS Keychain item and uses a
short-lived isolated `CODEX_HOME` directory when querying the Codex app-server.

It does not provide automatic account rotation, shared credentials, account
resale, or a mechanism to bypass service limits. Users must follow the terms
and policies that apply to the OpenAI services they use.

## Do not report secrets in an issue

Never include access tokens, refresh tokens, API keys, `auth.json`, Keychain
exports, screenshots containing account data, or local state files in a public
issue or pull request. If credentials may have been exposed, revoke or rotate
them first and remove them from the repository history.

## Reporting a vulnerability

Please open a private security report through the repository's configured
security contact. If private reporting is unavailable, open an issue that
contains only a short, non-sensitive description and ask for a private
follow-up. Include the affected version, macOS version, reproduction steps
without secrets, and the expected and actual behavior.

