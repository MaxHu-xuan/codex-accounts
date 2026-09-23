# Security policy

## Scope

This project is a local macOS account and quota viewer for Codex. It stores
each account's cached login state in a separate macOS Keychain item and uses a
short-lived isolated `CODEX_HOME` directory when querying the Codex app-server.

It does not provide automatic account rotation, shared credentials, account
resale, or a mechanism to bypass service limits. Users must follow the terms
and policies that apply to the OpenAI services they use.

## Keychain identity across updates

An ad-hoc code signature is tied to a particular build. Keychain access granted
to one such build may not transfer to the next build. For a local installation
with an available signing certificate, pass its identity through
`CODEX_ACCOUNTS_SIGN_IDENTITY` when running `tools/build-app.sh`. Keep the bundle
identifier and signing identity consistent across updates. The script defaults
to ad-hoc signing when the variable is unset; it uses at most two build workers
by default (`CODEX_ACCOUNTS_BUILD_JOBS`). Signing alone is not notarization.

Never commit a personal certificate name, Team ID, private key, or signing
credentials. A certificate-signed binary carries its publisher identity; do not
publish a locally signed binary when that identity is meant to remain private.

Credential updates preserve the existing Keychain item and its access policy.
Each query session saves only changed login data and keeps its protected
recovery file if a save fails. The app does not grant access to all applications
or disable macOS authorization prompts.

## Do not report secrets in an issue

Never include access tokens, refresh tokens, API keys, `auth.json`, Keychain
exports, screenshots containing account data, or local state files in a public
issue or pull request. If credentials may have been exposed, revoke or rotate
them first and remove them from the repository history.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository when it
is available. If private reporting is unavailable, open an issue that
contains only a short, non-sensitive description and ask for a private
follow-up. Include the affected version, macOS version, reproduction steps
without secrets, and the expected and actual behavior.
