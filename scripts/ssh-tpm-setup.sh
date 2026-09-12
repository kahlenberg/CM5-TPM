#!/usr/bin/env bash
#
# NAME
#     ssh-tpm-setup.sh -- create a PKCS#11 token in the TPM and use it for SSH auth
#
# SYNOPSIS
#     ./scripts/ssh-tpm-setup.sh <user@host> [token-label] [key-label]
#
#     user@host    remote account to install the public key on
#     token-label  PKCS#11 token name (default: tpm-token)
#     key-label    key name within the token (default: ssh-key)
#
# DESCRIPTION
#     Sets up SSH public key authentication where the private key is generated
#     inside the TPM and never exists outside it.
#
#       tpm2_ptool init       creates a primary object and the local SQLite
#                             store that tracks tokens and keys,
#       tpm2_ptool addtoken   creates a PIN-protected token; the SO PIN is for
#                             token administration, the user PIN for everyday
#                             key operations,
#       tpm2_ptool addkey     generates an RSA-2048 key pair inside the token --
#                             the private half is created in the TPM and is
#                             never exported,
#       ssh-keygen -D         reads the public key out of the token in standard
#                             SSH format and appends it to the remote's
#                             authorized_keys (prompts for the remote password
#                             once),
#       ssh -I                authenticates through the PKCS#11 library, which
#                             asks the TPM to sign the server's challenge.
#
#     PINs default to 1234 here because this is a demo. Change SO_PIN/USER_PIN
#     below before using this for anything real.
#
# REQUIREMENTS
#     libtpm2-pkcs11-1, libtpm2-pkcs11-tools, openssh-client
#
# SEE ALSO
#     ssh-tpm-test.sh    prove the TPM key specifically is what logged you in
#     ssh-tpm-remove.sh  remove the key from the remote and from the TPM
#
set -euo pipefail

REMOTE="${1:?usage: ssh-tpm-setup.sh <user@host> [token-label] [key-label]}"
TOKEN_LABEL="${2:-tpm-token}"
KEY_LABEL="${3:-ssh-key}"
SO_PIN=1234
USER_PIN=1234

echo "[1/4] Creating PKCS#11 store and token '$TOKEN_LABEL'"
tpm2_ptool init
tpm2_ptool addtoken --pid=1 --label="$TOKEN_LABEL" --sopin="$SO_PIN" --userpin="$USER_PIN"

echo
echo "[2/4] Generating an RSA-2048 key '$KEY_LABEL' inside the TPM"
tpm2_ptool addkey --algorithm=rsa2048 --label="$TOKEN_LABEL" \
    --key-label="$KEY_LABEL" --userpin="$USER_PIN"

echo
echo "[3/4] Locating the PKCS#11 provider library"
PKCS11_LIB="$(find /usr/lib -name 'libtpm2_pkcs11.so*' | head -1)"
# Typically /usr/lib/aarch64-linux-gnu/libtpm2_pkcs11.so.1
[[ -n "$PKCS11_LIB" ]] || { echo "libtpm2_pkcs11.so not found." >&2; exit 1; }
echo "      -> $PKCS11_LIB"

echo
echo "[4/4] Installing the public key on $REMOTE (password prompt expected)"
ssh-keygen -D "$PKCS11_LIB" | \
    ssh "$REMOTE" "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

echo
echo "[+] Done. Log in with:"
echo "    ssh -I $PKCS11_LIB $REMOTE"
