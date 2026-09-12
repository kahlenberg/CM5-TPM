#!/usr/bin/env bash
#
# NAME
#     pcr-seal-unseal.sh -- seal a secret to the current PCR state and unseal it again
#
# SYNOPSIS
#     ./scripts/pcr-seal-unseal.sh [secret-string] [pcr-list]
#
#     secret-string  text to seal      (default: "SECRET")
#     pcr-list       PCR bank/indices  (default: sha256:0,1,2)
#
# DESCRIPTION
#     Demonstrates measured-state-bound storage: a secret that the TPM will only
#     release while the platform measurements still match those recorded at
#     seal time.
#
#       tpm2_pcrread          prints the current PCR values -- PCR 0 firmware,
#                             PCR 1 firmware configuration, PCR 2 option ROMs,
#       tpm2_createprimary    parent key in the owner hierarchy,
#       tpm2_createpolicy     digest of the selected PCR values -> policy.bin,
#       tpm2_create           seals the secret under that policy; the resulting
#                             seal.pub/seal.priv blobs are useless without both
#                             this TPM and matching PCR values,
#       tpm2_load             loads the blobs back to get an object handle,
#       tpm2_startauthsession opens a policy session,
#       tpm2_policypcr        asserts the PCRs still match policy.bin,
#       tpm2_unseal           releases the plaintext -- only if they do,
#       tpm2_flushcontext     frees the session handle.
#
#     If the boot chain changes, tpm2_policypcr/tpm2_unseal fail and the secret
#     stays locked inside the TPM. That is the whole point.
#
# REQUIREMENTS
#     tpm2-tools; access to /dev/tpmrm0 -- either prefix commands with sudo, or
#     run `sudo usermod -aG tss $USER` once and log back in.
#
# OUTPUT
#     ./primary.ctx ./policy.bin ./secret.txt ./seal.pub ./seal.priv
#     ./seal.ctx ./session.ctx   -- remove with cleanup.sh
#
set -euo pipefail

SECRET="${1:-SECRET}"
PCRS="${2:-sha256:0,1,2}"

echo "[1/4] Current PCR values ($PCRS)"
tpm2_pcrread "$PCRS"

echo
echo "[2/4] Creating primary key and PCR policy"
tpm2_createprimary -C o -c primary.ctx
tpm2_createpolicy --policy-pcr -l "$PCRS" -L policy.bin

echo
echo "[3/4] Sealing the secret under that policy"
printf '%s\n' "$SECRET" > secret.txt
tpm2_create -C primary.ctx -L policy.bin -i secret.txt -u seal.pub -r seal.priv
tpm2_load -C primary.ctx -u seal.pub -r seal.priv -c seal.ctx

echo
echo "[4/4] Unsealing -- requires a policy session that satisfies the PCR digest"
tpm2_startauthsession --policy-session -S session.ctx
trap 'tpm2_flushcontext session.ctx 2>/dev/null || true' EXIT
tpm2_policypcr -S session.ctx -l "$PCRS"
echo -n "      unsealed: "
tpm2_unseal -c seal.ctx -p session:session.ctx
