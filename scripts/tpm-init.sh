#!/usr/bin/env bash
#
# NAME
#     tpm-init.sh -- clear the TPM and create a fresh owner-hierarchy primary key
#
# SYNOPSIS
#     sudo ./scripts/tpm-init.sh
#
# DESCRIPTION
#     Brings the TPM to a known-good starting state for the demos in this repo:
#
#       tpm2_clear         wipes the storage hierarchy -- every key, sealed
#                          object and persistent handle created under it,
#       tpm2_createprimary derives a new primary key in the owner hierarchy and
#                          saves its context to ./primary.ctx for later use.
#
#     WARNING: tpm2_clear is destructive and irreversible. Anything already
#     sealed to this TPM (LUKS enrollments, PKCS#11 tokens, TPM-backed TLS
#     keys) becomes permanently unrecoverable. Do not run it on a system whose
#     root filesystem is unlocked by the TPM.
#
# REQUIREMENTS
#     tpm2-tools; access to /dev/tpmrm0 (run as root or join the `tss` group)
#
# OUTPUT
#     ./primary.ctx -- primary key context, consumed by pcr-seal-unseal.sh
#
set -euo pipefail

read -rp "This will CLEAR the TPM and destroy all existing keys. Continue? [y/N] " reply
[[ "$reply" == [yY] ]] || { echo "Aborted."; exit 1; }

tpm2_clear
tpm2_createprimary -C o -c primary.ctx
echo "TPM initialized"
