#!/usr/bin/env bash
#
# NAME
#     ssh-tpm-test.sh -- prove the TPM key, and nothing else, is authenticating you
#
# SYNOPSIS
#     ./scripts/ssh-tpm-test.sh <user@host> [pkcs11-lib]
#
# DESCRIPTION
#     A successful `ssh -I ...` login does not by itself prove the TPM was used:
#     ssh may have fallen back to a key file in ~/.ssh, to a loaded ssh-agent
#     identity, or to password auth. This script disables every one of those
#     paths, leaving the PKCS#11 provider as the only way in:
#
#       -o IdentitiesOnly=yes            ignore default identity files,
#       -o IdentityAgent=none            ignore any running ssh-agent,
#       -o PreferredAuthentications=publickey
#       -o PasswordAuthentication=no     no password fallback,
#       -I <lib>                         use the TPM PKCS#11 provider,
#       -vv                              verbose, so you can see which key is offered.
#
#     If the login succeeds, it was the TPM key. If it fails, something in the
#     setup is incomplete.
#
# REQUIREMENTS
#     libtpm2-pkcs11-1, openssh-client, a token created by ssh-tpm-setup.sh
#
set -euo pipefail

REMOTE="${1:?usage: ssh-tpm-test.sh <user@host> [pkcs11-lib]}"
PKCS11_LIB="${2:-$(find /usr/lib -name 'libtpm2_pkcs11.so*' | head -1)}"
[[ -n "$PKCS11_LIB" ]] || { echo "libtpm2_pkcs11.so not found." >&2; exit 1; }

echo "[*] TPM-only login attempt via $PKCS11_LIB"
ssh -vv \
    -o IdentitiesOnly=yes \
    -o IdentityAgent=none \
    -o PreferredAuthentications=publickey \
    -o PasswordAuthentication=no \
    -I "$PKCS11_LIB" "$REMOTE"
