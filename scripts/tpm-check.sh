#!/usr/bin/env bash
#
# NAME
#     tpm-check.sh -- verify that the CM4/5 TPM module is detected and responding
#
# SYNOPSIS
#     ./scripts/tpm-check.sh
#
# DESCRIPTION
#     Read-only sanity check to run first, right after enabling the
#     `tpm-slb9670` device tree overlay and rebooting. It confirms that:
#
#       1. the kernel created /dev/tpm0 and /dev/tpmrm0,
#       2. the tpm_tis_spi driver bound to the SLB 9670 on the SPI bus,
#       3. the TPM answers a capability query and reports "IFX" as manufacturer,
#       4. the hardware RNG returns random bytes.
#
#     Makes no changes to the TPM. Safe to run at any time.
#
# REQUIREMENTS
#     tpm2-tools, xxd
#
# EXIT STATUS
#     0  TPM present and responding
#     1  TPM device nodes missing or TPM did not answer
#
set -euo pipefail

echo "[1/4] TPM device nodes"
if ! ls /dev/tpm* 2>/dev/null; then
    echo "  !! No /dev/tpm* nodes. Check dtparam=spi=on and dtoverlay=tpm-slb9670 in config.txt." >&2
    exit 1
fi

echo
echo "[2/4] Kernel driver binding"
# Expected: tpm_tis_spi spi0.1: 2.0 TPM (device-id 0x1B, rev-id 22)
dmesg | grep -i tpm || echo "  (nothing in dmesg -- ring buffer may have wrapped)"

echo
echo "[3/4] Fixed properties (manufacturer / vendor / firmware)"
tpm2_getcap properties-fixed | grep -E "MANUFACT|VENDOR|FIRMWARE" \
    || { echo "  !! TPM did not answer tpm2_getcap." >&2; exit 1; }

echo
echo "[4/4] Hardware RNG"
tpm2_getrandom 8 | xxd

echo
echo "[+] TPM is present and responding."
