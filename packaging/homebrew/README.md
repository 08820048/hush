# Homebrew

Templates for a Homebrew tap (a separate repository named `homebrew-tap`):

- `hush.rb.template` → `Casks/hush.rb`: the menu bar app
- `hush-cli.rb.template` → `Formula/hush-cli.rb`: the `hush` command-line tool

After a **signed and notarized** release, fill in the version and checksums:

```sh
scripts/homebrew.sh 0.1.0        # downloads SHA256SUMS.txt from the GitHub release
```

The filled files are written to `packaging/homebrew/out/`. Copy them into the tap, then users install with:

```sh
brew install --cask 08820048/tap/hush
brew install 08820048/tap/hush-cli
```

Only publish signed and notarized builds through Homebrew. Gatekeeper blocks ad-hoc builds.
