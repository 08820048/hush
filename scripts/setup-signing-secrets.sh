#!/bin/bash
# Stores the Developer ID certificate and the notarization API key as GitHub Actions secrets,
# so tagged releases are signed and notarized (see .github/workflows/release.yml).
#
#   scripts/setup-signing-secrets.sh path/to/DeveloperID.p12 path/to/AuthKey_XXXXXXXXXX.p8
#
# Run it yourself: it asks for the .p12 password and the API key's issuer ID interactively,
# and passes everything straight to `gh secret set`. Nothing is printed or written elsewhere.
set -euo pipefail
cd "$(dirname "$0")/.."

P12=${1:?usage: scripts/setup-signing-secrets.sh <DeveloperID.p12> <AuthKey_KEYID.p8>}
P8=${2:?usage: scripts/setup-signing-secrets.sh <DeveloperID.p12> <AuthKey_KEYID.p8>}
REPO=${REPO:-08820048/hush}
[[ -f "$P12" ]] || { echo "error: $P12 not found" >&2; exit 1; }
[[ -f "$P8" ]] || { echo "error: $P8 not found" >&2; exit 1; }
command -v gh >/dev/null || { echo "error: GitHub CLI (gh) is required" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: run 'gh auth login' first" >&2; exit 1; }

read -r -s -p "Password of $(basename "$P12"): " P12_PASSWORD; echo
export P12_PASSWORD  # openssl reads it from the environment, never from the command line

# Read the certificate out of the .p12 to check it and to get the exact identity name.
CERT=$(openssl pkcs12 -in "$P12" -nokeys -clcerts -passin env:P12_PASSWORD 2>/dev/null \
    || openssl pkcs12 -legacy -in "$P12" -nokeys -clcerts -passin env:P12_PASSWORD 2>/dev/null) \
    || { echo "error: could not open the .p12 (wrong password?)" >&2; exit 1; }
SUBJECT=$(printf '%s\n' "$CERT" | openssl x509 -noout -subject -nameopt utf8,sep_multiline)
IDENTITY=$(printf '%s\n' "$SUBJECT" | sed -n 's/^ *CN=//p')
TEAM_ID=$(printf '%s\n' "$SUBJECT" | sed -n 's/^ *OU=//p' | head -1)
EXPIRES=$(printf '%s\n' "$CERT" | openssl x509 -noout -enddate | cut -d= -f2)
[[ "$IDENTITY" == "Developer ID Application:"* ]] || { echo "error: this is not a Developer ID Application certificate: $IDENTITY" >&2; exit 1; }
KEY_COUNT=$(openssl pkcs12 -in "$P12" -nocerts -nodes -passin env:P12_PASSWORD 2>/dev/null | grep -c "PRIVATE KEY-----" \
    || openssl pkcs12 -legacy -in "$P12" -nocerts -nodes -passin env:P12_PASSWORD 2>/dev/null | grep -c "PRIVATE KEY-----" || true)
[[ "${KEY_COUNT:-0}" -ge 2 ]] || { echo "error: the .p12 has no private key; export the certificate together with its key" >&2; exit 1; }

# The key ID is part of the file name Apple gives the download (AuthKey_<KEYID>.p8).
KEY_ID=$(basename "$P8" .p8); KEY_ID=${KEY_ID#AuthKey_}
read -r -p "API key ID [$KEY_ID]: " INPUT; KEY_ID=${INPUT:-$KEY_ID}
read -r -p "Issuer ID (App Store Connect › Users and Access › Integrations): " ISSUER
[[ -n "$KEY_ID" && -n "$ISSUER" ]] || { echo "error: key ID and issuer ID are required" >&2; exit 1; }

echo
echo "Identity: $IDENTITY"
echo "Team ID:  $TEAM_ID   (expires $EXPIRES)"
echo "API key:  $KEY_ID"
echo "Repo:     $REPO"
read -r -p "Store these as GitHub Actions secrets? [y/N] " OK
[[ "$OK" == [yY] ]] || { echo "Cancelled."; exit 1; }

base64 -i "$P12" | gh secret set DEVELOPER_ID_P12 --repo "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set DEVELOPER_ID_P12_PASSWORD --repo "$REPO"
printf '%s' "$IDENTITY" | gh secret set DEVELOPER_ID --repo "$REPO"
printf '%s' "$TEAM_ID" | gh secret set TEAM_ID --repo "$REPO"
base64 -i "$P8" | gh secret set NOTARY_KEY_P8 --repo "$REPO"
printf '%s' "$KEY_ID" | gh secret set NOTARY_KEY_ID --repo "$REPO"
printf '%s' "$ISSUER" | gh secret set NOTARY_ISSUER --repo "$REPO"
unset P12_PASSWORD

echo
echo "Done. The next tagged release will be signed and notarized."
echo "Keep the .p12 and .p8 somewhere safe (or delete them); Apple lets you download a .p8 only once."
