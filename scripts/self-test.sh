#!/usr/bin/env bash
#
# NAME
#     self-test.sh -- end-to-end functional test of the TPM key and signing path
#
# SYNOPSIS
#     ./scripts/self-test.sh
#
# DESCRIPTION
#     Exercises the full create/load/sign cycle to prove the SPI link and the
#     TPM's crypto engine both work:
#
#       tpm2_getrandom      hardware RNG returns 8 random bytes,
#       tpm2_createprimary  creates a parent key in the owner hierarchy,
#       tpm2_create         creates a child key under that parent,
#       tpm2_load           loads the child key back into the TPM,
#       tpm2_sign           signs a message with the child key inside the TPM,
#       tpm2_pcrread        prints the current boot measurements (PCR 0,1,2).
#
#     Creates only transient objects plus files in the working directory --
#     nothing is made persistent in TPM NV storage. Run cleanup.sh afterwards
#     to remove the artifacts.
#
# REQUIREMENTS
#     tpm2-tools, xxd; access to /dev/tpmrm0 (run as root or join the `tss` group)
#
# OUTPUT
#     ./primary.ctx ./key.pub ./key.priv ./key.ctx ./data.txt ./sig.bin
#
set -e
echo "[+] TPM self test"
tpm2_getrandom 8 | xxd
tpm2_createprimary -C o -c primary.ctx
tpm2_create -C primary.ctx -u key.pub -r key.priv
tpm2_load -C primary.ctx -u key.pub -r key.priv -c key.ctx
echo "hello" > data.txt
tpm2_sign -c key.ctx -g sha256 -o sig.bin data.txt
tpm2_pcrread sha256:0,1,2
echo "[+] Done"
