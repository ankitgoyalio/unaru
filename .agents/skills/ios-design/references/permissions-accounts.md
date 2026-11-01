# Permissions and accounts

## Protected resources

Request protected resources when the current feature explains the need; launch-time requests fit only resources essential to the app's initial function. Prefer system pickers or one-time access when they satisfy the task. Write a specific purpose string and provide a useful denied or limited-access state.

The current context is usually the permission explanation. Use a pre-alert only when essential details are missing; it has one neutral Continue/Next action that opens the system request, rather than imitating consent. Check current Apple policy before claiming tracking-prompt compliance.

## Accounts

Require account creation where the feature needs authenticated capabilities; use passkeys or system sign-in where applicable. Check current Apple account requirements before claiming compliance.

Sources: [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy), [Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts).
