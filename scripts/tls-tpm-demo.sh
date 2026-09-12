#!/usr/bin/env bash
#
# NAME
#     tls-tpm-demo.sh -- TLS server and client using a key that lives in the TPM
#
# SYNOPSIS
#     ./scripts/tls-tpm-demo.sh [port] [common-name]
#
#     port         TLS listen port    (default: 8443)
#     common-name  certificate CN     (default: tpm-tls.local)
#
# DESCRIPTION
#     Generates an RSA-2048 key inside the TPM, self-signs a certificate with
#     it, starts an OpenSSL TLS server using that key, and connects a client to
#     it. Every handshake triggers a private key operation inside the chip; the
#     private key bytes never touch the disk.
#
#       openssl genpkey -provider tpm2
#                       creates the key pair in the TPM. The PEM written out
#                       holds only a reference (handle) to the TPM object,
#       openssl pkey -pubout
#                       extracts the public key -- safe to distribute,
#       openssl req -new -x509
#                       self-signs a certificate, the signature being produced
#                       by the TPM,
#       openssl s_server / s_client
#                       complete a real handshake against that key.
#
#     TPM2OPENSSL_TCTI=device:/dev/tpmrm0 points the provider at the kernel
#     resource manager. Without it the provider talks to the TPM directly and
#     exhausts its limited object context slots ("out of memory for object
#     contexts"). Use `sudo -E` if you run this as root, so the variable
#     survives.
#
#     TLS 1.2 is forced because some tpm2-openssl builds hit a context
#     duplication bug on TLS 1.3.
#
# REQUIREMENTS
#     tpm2-tools, tpm2-openssl, openssl
#
# OUTPUT
#     ./rsa_tpm_key.pem ./rsa_tpm_key.pub.pem ./cert.pem
#
set -euo pipefail

PORT="${1:-8443}"
CN="${2:-tpm-tls.local}"
PROV=(-provider tpm2 -provider default)

export TPM2OPENSSL_TCTI=device:/dev/tpmrm0

echo "[0/5] Basic TPM check"
tpm2_getrandom 8 | xxd

echo
echo "[1/5] Generating a TPM-backed RSA-2048 key (private half stays in the TPM)"
openssl genpkey "${PROV[@]}" -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out rsa_tpm_key.pem

echo
echo "[2/5] Extracting the public key"
openssl pkey -in rsa_tpm_key.pem "${PROV[@]}" -pubout -out rsa_tpm_key.pub.pem

echo
echo "[3/5] Self-signing a certificate (signature computed inside the TPM)"
openssl req -new -x509 -key rsa_tpm_key.pem "${PROV[@]}" -subj "/CN=$CN" -days 365 -out cert.pem

echo
echo "[4/5] Starting the TLS server on port $PORT"
openssl s_server -accept "$PORT" -cert cert.pem -key rsa_tpm_key.pem "${PROV[@]}" -www -tls1_2 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
sleep 2

echo
echo "[5/5] Connecting as client -- a completed handshake proves the chain works"
if echo | openssl s_client -connect "127.0.0.1:$PORT" -servername "$CN" -tls1_2 2>&1 | \
       grep -E "Verify return code|Protocol|Cipher"; then
    echo
    echo "[+] TLS handshake against the TPM-held key succeeded."
else
    echo
    echo "!! Handshake failed. If the error mentions 'cannot duplicate context' or" >&2
    echo "   'out of memory for object contexts', flush stale TPM handles and retry:" >&2
    echo "     tpm2_flushcontext -t && tpm2_flushcontext -l && tpm2_flushcontext -s" >&2
    exit 1
fi
