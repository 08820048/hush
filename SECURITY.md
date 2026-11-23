# Security

## Threat model

Hush protects against:

- **Weak or reused passwords**: secrets come from the system CSPRNG with uniform sampling.
- **Clipboard leftovers**: copied secrets are marked `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` so clipboard managers skip them. They are cleared after a delay (30 s by default), but only if the clipboard still holds the same item.
- **Leaks to the network**: the app runs in the App Sandbox **without** the `com.apple.security.network.client` entitlement. There is no telemetry, no analytics and no crash reporting. Website password rules are bundled in the app (from Apple's password-manager-resources), so looking up a site never sends anything anywhere.
- **File access**: the only other entitlement is `com.apple.security.files.user-selected.read-write`. It lets Hush read or write exactly the file you pick in an Open or Save panel, for importing and exporting presets. Preset files contain settings only, never passwords.
- **Leftovers on disk**: secrets are never written to disk. The optional history lives in memory only. It is wiped after 5 minutes, on screen lock, on sleep and on quit.

Hush does **not** protect against a machine that is already compromised (malware, keyloggers, a malicious process reading memory). Swift strings cannot be reliably zeroed in memory. Hush drops references to secrets as soon as it can, but cannot guarantee they are erased.

## Generation

- Randomness comes only from `SecRandomCopyBytes`. `SecureRandom.uniform(_:)` uses rejection sampling to avoid modulo bias.
- The "every class at least once" rule regenerates the whole string until it passes. It never forces characters into fixed positions. The reported entropy counts the strings the rule excludes exactly, using inclusion–exclusion.
- PIN mode excludes repeats, runs, doubled digits and date-like PINs. Entropy is computed from the exact size of the remaining set.
- Tests include chi-square checks on the uniformity of the generator and of the character distribution.

## Direct paste

Pressing ⌘↩ sends a ⌘V keystroke to the app that was frontmost, which requires Accessibility permission. This is optional. Without the permission, Hush only copies.

## URL scheme and Shortcuts

`hush://` URLs and the Shortcuts actions can only create a **new** secret. Nothing can read back a secret that was generated earlier, and history is never exposed. Any app or web page that opens a `hush://generate` URL can make Hush put a fresh password on the clipboard, but it cannot see that password. Browsers ask before opening apps through custom URL schemes.

Custom presets store settings only (length, character classes, word count and so on), never passwords. They live in the app's UserDefaults.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub Security Advisories on this repository instead of opening a public issue.
