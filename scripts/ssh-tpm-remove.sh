#!/usr/bin/env bash
#
# NAME
#     ssh-tpm-remove.sh -- list and delete TPM-backed SSH keys / PKCS#11 tokens
#
# SYNOPSIS
#     ./scripts/ssh-tpm-remove.sh list  [token-label]
#     ./scripts/ssh-tpm-remove.sh pubkey [pkcs11-lib]
#     ./scripts/ssh-tpm-remove.sh objdel <object-id>
#     ./scripts/ssh-tpm-remove.sh rmtoken <token-label>
#
# DESCRIPTION
#     IMPORTANT: remove the public key from every remote ~/.ssh/authorized_keys
#     BEFORE deleting the key from the TPM. Once deleted, the private key is
#     gone permanently and you lose access to any host still expecting it.
#     Start with `pubkey`, clean up the remotes, then delete.
#
#       pubkey   ssh-keygen -D prints the public key so you can identify the
#                exact line to strip from authorized_keys on each remote.
#
#       list     tpm2_ptool listprimaries / listtokens / listobjects -- use this
#                to find the token label if you have forgotten it, and to get
#                the numeric object ids. An RSA key pair shows up as TWO
#                objects (private and public), usually sharing one CKA_LABEL.
#
#       objdel   deletes a single object by the plain integer `id` field from
#                `list`. Note: that is NOT the CKA_ID hex string -- objdel wants
#                the top-level `id` integer from the YAML output.
#
#       rmtoken  deletes the whole token and every key inside it at once.
#
# REQUIREMENTS
#     libtpm2-pkcs11-tools, openssh-client
#
set -euo pipefail

cmd="${1:-}"
case "$cmd" in
  pubkey)
    lib="${2:-$(find /usr/lib -name 'libtpm2_pkcs11.so*' | head -1)}"
    echo "# Remove this line from ~/.ssh/authorized_keys on every remote:"
    ssh-keygen -D "$lib"
    echo "# e.g. ssh user@host \"sed -i '/PASTE_PUBLIC_KEY_HERE/d' ~/.ssh/authorized_keys\""
    ;;
  list)
    label="${2:-tpm-token}"
    tpm2_ptool listprimaries
    tpm2_ptool listtokens --pid=1
    tpm2_ptool listobjects --label="$label"
    ;;
  objdel)
    id="${2:?usage: ssh-tpm-remove.sh objdel <object-id>}"
    tpm2_ptool objdel "$id"
    ;;
  rmtoken)
    label="${2:?usage: ssh-tpm-remove.sh rmtoken <token-label>}"
    read -rp "Delete token '$label' and ALL keys inside it? [y/N] " reply
    [[ "$reply" == [yY] ]] || { echo "Aborted."; exit 1; }
    tpm2_ptool rmtoken --label="$label"
    ;;
  *)
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
