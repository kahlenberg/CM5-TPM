#!/usr/bin/env bash
#
# NAME
#     luks-tpm-loop-demo.sh -- TPM-backed LUKS unlock demo on a throwaway loop device
#
# SYNOPSIS
#     sudo ./scripts/luks-tpm-loop-demo.sh [image-file] [size-mb]
#
#     image-file   backing file to create   (default: ./test.img)
#     size-mb      size of that file in MiB (default: 50)
#
# DESCRIPTION
#     Runs the complete LUKS2 + TPM2 enrollment flow against a file-backed loop
#     device, so nothing on the real storage is ever touched. Cleanup is just
#     deleting a file.
#
#       dd                     creates a zero-filled backing file,
#       losetup -f --show      attaches it as /dev/loopN,
#       cryptsetup luksFormat  initialises LUKS2 on the loop device -- you are
#                              prompted for a passphrase, which stays as the
#                              recovery fallback in keyslot 0,
#       systemd-cryptenroll    seals a generated key inside the TPM and adds it
#                              as a second keyslot,
#       systemd-cryptsetup attach
#                              simulates the boot-time unlock: the key comes
#                              from the TPM, no passphrase prompt,
#       systemd-cryptsetup detach / losetup -d / rm
#                              tear everything down again.
#
#     The script is interactive: cryptsetup asks you to type YES and to set a
#     passphrase, and systemd-cryptenroll asks for that passphrase once.
#
# NOTES
#     On Raspberry Pi, systemd-cryptenroll may warn that the selected PCRs are
#     not initialised. That is expected -- Pi firmware does not implement
#     measured boot the way a PC does, so PCR-based anti-tamper enforcement is
#     not active. The encryption itself still works.
#
#     Never point this script at a real partition. For that flow see the
#     "Option A" section of the README, and read the warning there first.
#
# REQUIREMENTS
#     cryptsetup, systemd (>= 248) with systemd-cryptenroll, tpm2-tools; root
#
set -euo pipefail

IMG="${1:-test.img}"
SIZE_MB="${2:-50}"
MAPPER_NAME="test-vol"
LOOP=""

cleanup() {
    echo
    echo "[*] Tearing down"
    systemd-cryptsetup detach "$MAPPER_NAME" 2>/dev/null || true
    [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true
    rm -f "$IMG"
    echo "[*] Removed $IMG"
}
trap cleanup EXIT

[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ -e "$IMG" ]] && { echo "$IMG already exists -- refusing to overwrite." >&2; exit 1; }

echo "[1/6] Creating ${SIZE_MB} MiB backing file $IMG"
dd if=/dev/zero of="$IMG" bs=1M count="$SIZE_MB" status=none

echo "[2/6] Attaching as loop device"
LOOP="$(losetup -f "$IMG" --show)"
echo "      -> $LOOP"

echo "[3/6] Formatting with LUKS2 (you will set a passphrase -- keep it, it is the fallback)"
cryptsetup luksFormat "$LOOP"

echo "[4/6] Enrolling the TPM as an automatic unlock key"
systemd-cryptenroll --tpm2-device=auto "$LOOP"

echo "[5/6] Simulating boot unlock -- the TPM provides the key"
systemd-cryptsetup attach "$MAPPER_NAME" "$LOOP" - tpm2-device=auto
ls -l "/dev/mapper/$MAPPER_NAME"

echo "[6/6] Unlocked without a passphrase. Success."
