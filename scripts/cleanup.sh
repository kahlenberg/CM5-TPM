#!/usr/bin/env bash
#
# NAME
#     cleanup.sh -- delete the on-disk artifacts left behind by the demo scripts
#
# SYNOPSIS
#     ./scripts/cleanup.sh
#
# DESCRIPTION
#     Removes the key contexts, public/private blobs, policy digests and test
#     data written into the current directory by self-test.sh,
#     pcr-seal-unseal.sh and friends.
#
#     Touches only files in the working directory. It does NOT clear the TPM,
#     does not remove persistent handles, and does not touch PKCS#11 tokens --
#     use tpm-init.sh (destructive) or ssh-tpm-remove.sh for those.
#
set -euo pipefail
rm -f ./*.ctx ./*.pub ./*.priv ./*.bin data.txt secret.txt
echo "cleaned"
