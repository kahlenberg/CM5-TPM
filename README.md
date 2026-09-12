
# CM4/CM5 TPM 2.0 Demo

Hardware-backed security demos for Raspberry Pi CM4/5 + TPM 2.0.

## Quick start

Enable SPI and load the TPM driver overlay in config.txt so the system can communicate with the TPM 2.0 module at boot:

config.txt:
```
dtparam=spi=on
dtoverlay=tpm-slb9670
```
Install the required TPM tooling and basic utilities, then verify the TPM is responsive by requesting random bytes and running a simple self-test:

```
sudo apt update
sudo apt install tpm2-tools tpm2-abrmd openssl xxd

tpm2_getrandom 8 | xxd
./scripts/self-test.sh
```

# Examples
## LUKS TPM

Install disk encryption support and initialize a LUKS volume, then bind it to the TPM so it can be unlocked automatically based on platform state.

`cryptsetup luksFormat` initializes a partition with LUKS encryption. You set a passphrase during this step — keep it safe as a recovery fallback.

`systemd-cryptenroll` then adds the TPM as a second unlock method. On subsequent boots, the TPM automatically provides the unlock key if the system state (PCR measurements) matches what was recorded at enrollment time — no passphrase prompt needed.

> **Warning:** Do not run `luksFormat` on `/dev/mmcblk0p2` if that is your live root partition — it will destroy the running OS. Use the loop device test below instead.

### Option A — real partition

```
sudo apt install cryptsetup

cryptsetup luksFormat /dev/mmcblk0p2

systemd-cryptenroll --tpm2-device=auto /dev/mmcblk0p2
```

### Option B — loop device (safe, no real disk needed)

This approach creates a temporary file on disk, attaches it as a virtual block device, and runs the full LUKS + TPM flow against that. Nothing touches your real storage. Cleanup is just deleting a file.

`dd` creates a 50 MB file filled with zeros. This becomes the backing store for the virtual disk.

`losetup -f --show` finds the next free loop device and attaches the file to it, making it appear as a real block device like `/dev/loop0`.

`cryptsetup luksFormat` initializes LUKS encryption on the loop device. You will set a passphrase here — it is needed for enrollment and as a recovery fallback.

`systemd-cryptenroll --tpm2-device=auto` seals a generated key inside the TPM and adds it as a second LUKS keyslot. After this, the TPM can unlock the volume automatically without the passphrase.

`systemd-cryptsetup attach` simulates what happens at boot — it asks the TPM for the key and opens the encrypted volume, making it available as `/dev/mapper/test-vol`.

`systemd-cryptsetup detach` closes the mapped volume when you are done.

`losetup -d` detaches the loop device. `rm test.img` removes the backing file completely.

```
# Create a 50 MB test image as a backing file
dd if=/dev/zero of=test.img bs=1M count=50

# Attach it as a loop device (note the device name printed, e.g. /dev/loop0)
sudo losetup -f test.img --show

# Initialize LUKS encryption on the loop device
sudo cryptsetup luksFormat /dev/loop0

# Enroll the TPM as an automatic unlock key (slot 1)
sudo systemd-cryptenroll --tpm2-device=auto /dev/loop0

# Simulate boot unlock — TPM provides the key automatically
sudo systemd-cryptsetup attach test-vol /dev/loop0 - tpm2-device=auto

# Verify the decrypted volume is available
ls /dev/mapper/test-vol

# Close the volume
sudo systemd-cryptsetup detach test-vol

# Clean up — detach loop device and delete the image
sudo losetup -d /dev/loop0
rm test.img
```

> **Note on PCR warnings:** On Raspberry Pi, `systemd-cryptenroll` may warn that selected PCRs are not initialized. This is expected — the Pi firmware does not implement measured boot the same way a PC does, so PCR-based anti-tamper enforcement is not active. The encryption itself still works correctly.

## Sealing

Read selected PCR values, create a policy tied to those measurements, and seal a secret so it can only be unsealed when the system matches that state.

> **Note:** `tpm2-tools` commands require access to `/dev/tpmrm0`. Either prefix each command with `sudo`, or add your user to the `tss` group once and log back in:
> ```
> sudo usermod -aG tss $USER
> # log out and back in, then all commands below work without sudo
> ```

`tpm2_pcrread` prints the current PCR values — tamper-evident boot measurements. PCR 0 is firmware, PCR 1 is firmware configuration, PCR 2 is option ROMs. These values change if the boot chain is modified.

`tpm2_createprimary` creates a parent key in the TPM owner hierarchy. The sealed object will live under this parent. The context is saved to `primary.ctx` for use in subsequent commands.

`tpm2_createpolicy` calculates a digest of the current PCR values and writes it to `policy.bin`. This digest is what the TPM will check at unseal time.

`tpm2_create` seals the secret inside the TPM, locked to the policy. The output blobs (`seal.pub`, `seal.priv`) are stored on disk but are useless without the same TPM and matching PCR values.

`tpm2_load` loads those blobs back into the TPM to get an active object handle (`seal.ctx`).

`tpm2_startauthsession` opens a policy session — a temporary channel through which you prove conditions are met before the TPM grants access.

`tpm2_policypcr` replays the PCR policy inside the session, asserting that the current PCR values match the ones from `policy.bin`.

`tpm2_unseal` retrieves the plaintext secret from the TPM. It only succeeds if the policy session confirms that PCR values still match — i.e. nothing in the boot chain has changed since sealing.

`tpm2_flushcontext` closes the session handle to free TPM resources.

```
# Read current PCR values (informational)
sudo tpm2_pcrread sha256:0,1,2

# Create a primary key to use as the parent for sealing
sudo tpm2_createprimary -C o -c primary.ctx

# Create a policy tied to current PCR 0,1,2 values
sudo tpm2_createpolicy --policy-pcr -l sha256:0,1,2 -L policy.bin

# Seal the secret under that policy
echo "SECRET" > secret.txt
sudo tpm2_create -C primary.ctx -L policy.bin -i secret.txt -u seal.pub -r seal.priv
sudo tpm2_load -C primary.ctx -u seal.pub -r seal.priv -c seal.ctx

# Unseal: must satisfy the PCR policy via an authorized session
sudo tpm2_startauthsession --policy-session -S session.ctx
sudo tpm2_policypcr -S session.ctx -l sha256:0,1,2
sudo tpm2_unseal -c seal.ctx -p session:session.ctx
sudo tpm2_flushcontext session.ctx
```

## SSH TPM

Set up a PKCS#11 interface backed by the TPM, create a token and key inside the TPM, and use it for SSH authentication without exposing private key material.

`tpm2_ptool init` creates a primary object in the TPM and initializes the local database (an SQLite store) that tracks tokens and keys.

`tpm2_ptool addtoken` creates a named PKCS#11 token — a PIN-protected logical container for keys inside the TPM. The SO PIN is an admin PIN for token management; the user PIN is used for day-to-day key operations.

`tpm2_ptool addkey` generates an RSA key pair inside that token. The private key is created inside the TPM and never exported. `--label` targets the token to add the key into; `--key-label` names the key within that token.

`find /usr/lib -name "libtpm2_pkcs11.so*"` locates the PKCS#11 shared library. SSH uses this library as a bridge to the TPM — it handles the signing operation internally so the private key never leaves hardware.

`ssh-keygen -D` reads and prints the public key from the PKCS#11 token in standard SSH format, so it can be registered on remote hosts.

`ssh -I` tells SSH to use the PKCS#11 library for authentication instead of a key file. The library asks the TPM to sign the server's challenge; the private key never leaves the chip.

```
sudo apt install libtpm2-pkcs11-1 libtpm2-pkcs11-tools

tpm2_ptool init
tpm2_ptool addtoken --pid=1 --label="tpm-token" --sopin=1234 --userpin=1234
tpm2_ptool addkey --algorithm=rsa2048 --label="tpm-token" --key-label="ssh-key" --userpin=1234

# Find the PKCS#11 library path on your system
find /usr/lib -name "libtpm2_pkcs11.so*" | head -1
# Typically: /usr/lib/aarch64-linux-gnu/libtpm2_pkcs11.so.1

PKCS11_LIB=/usr/lib/aarch64-linux-gnu/libtpm2_pkcs11.so.1

# Export the public key and copy it to the remote host (will prompt for password)
ssh-keygen -D $PKCS11_LIB | ssh user@host "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Test login — the TPM will perform the private key operation internally
ssh -I $PKCS11_LIB user@host
```

### Testing SSH TPM authentication

To prove that the TPM key specifically is being used (and not a fallback identity file or ssh-agent), use the flags below. They disable every other authentication path — only the PKCS#11 provider remains. If login succeeds, it is the TPM key. If it fails, something in the setup is incomplete.

```
PKCS11_LIB=/usr/lib/aarch64-linux-gnu/libtpm2_pkcs11.so.1

# Force a TPM-only public key login with no agent, no password, and no fallback identities
ssh -vv -o IdentitiesOnly=yes -o IdentityAgent=none -o PreferredAuthentications=publickey -o PasswordAuthentication=no -I $PKCS11_LIB user@host
```

### Removing TPM SSH keys

> **Important:** Remove the public key from all remote `~/.ssh/authorized_keys` files *before* deleting the key from the TPM. Once deleted from the TPM, the private key is gone permanently and you will lose access to any host that still expects it.

`ssh-keygen -D` prints the public key so you can identify and remove the correct line from `authorized_keys` on the remote.

`tpm2_ptool listprimaries` and `listtokens` discover the actual token label — useful if you have forgotten it or used a non-default name.

`tpm2_ptool listobjects` shows all key objects in a token with their numeric `id` fields. Each RSA key pair appears as two objects: one private key and one public key, usually sharing the same `CKA_LABEL`.

`tpm2_ptool objdel` deletes a single object by its numeric `id` from `listobjects`. Note: this is not the `CKA_ID` hex string — it is the plain integer `id` field in the YAML output.

`tpm2_ptool rmtoken` removes the entire token and all keys inside it in one step.

```
# Print the public key to identify which line to remove from authorized_keys
PKCS11_LIB=/usr/lib/aarch64-linux-gnu/libtpm2_pkcs11.so.1
ssh-keygen -D $PKCS11_LIB
ssh user@host "sed -i '/PASTE_PUBLIC_KEY_HERE/d' ~/.ssh/authorized_keys"

# Discover the token label if you are not sure which one contains the SSH key
tpm2_ptool listprimaries
tpm2_ptool listtokens --pid=1

# List objects in the token once you know its label
tpm2_ptool listobjects --label="tpm-token"

# Delete both objects for the SSH key using the numeric id field from the list above
# Do not use the CKA_ID hex string here; objdel expects the top-level "id" integer.
tpm2_ptool objdel <private-object-id>
tpm2_ptool objdel <public-object-id>

# Or remove the entire token and all keys within it
tpm2_ptool rmtoken --label="tpm-token"

# Verify the key is gone — SSH should now fail
ssh -I $PKCS11_LIB user@host
```

## TLS TPM

Create a TPM-backed key and use it with OpenSSL for a local TLS server test. The private key is generated inside the TPM and never written to disk in plaintext. OpenSSL communicates with the TPM through the `tpm2` provider for all signing operations.

`openssl genpkey -provider tpm2` generates a key pair where the private portion is created and stored inside the TPM. The output PEM file contains only a reference (handle) to the TPM object, not the actual private key bytes.

`openssl pkey -pubout` extracts the public key from that TPM-backed reference, safe to distribute.

`openssl req -new -x509` creates a self-signed certificate using the TPM key to sign it. This proves the signing operation happened inside the hardware.

`openssl s_server` starts a TLS server using the TPM-backed key and certificate. Every TLS handshake triggers a private key operation inside the TPM.

`openssl s_client` connects and completes the TLS handshake. A successful connection confirms the full chain works: TPM key → certificate → TLS.

`TPM2OPENSSL_TCTI=device:/dev/tpmrm0` tells the OpenSSL TPM provider to use the resource manager device. Without this, the provider may talk directly to the TPM and exhaust its limited object context slots, causing `out of memory for object contexts` errors.

```
sudo apt update
sudo apt install tpm2-tools tpm2-openssl openssl

# Basic TPM check
tpm2_getrandom 8 | xxd

# Point the OpenSSL TPM provider at the resource manager.
# Use sudo -E if running as root to preserve this variable.
export TPM2OPENSSL_TCTI=device:/dev/tpmrm0

# Generate a TPM-backed RSA 2048 key — private key never leaves the TPM
openssl genpkey -provider tpm2 -provider default -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out rsa_tpm_key.pem

# Extract and save the public key (optional, informational)
openssl pkey -in rsa_tpm_key.pem -provider tpm2 -provider default -pubout -out rsa_tpm_key.pub.pem

# Create a self-signed certificate signed by the TPM key
openssl req -new -x509 -key rsa_tpm_key.pem -provider tpm2 -provider default -subj "/CN=tpm-tls.local" -days 365 -out cert.pem

# Start a TLS server using the TPM-backed key (use -tls1_2 to avoid a known
# context-duplication bug in some tpm2-openssl builds on TLS 1.3)
openssl s_server -accept 8443 -cert cert.pem -key rsa_tpm_key.pem -provider tpm2 -provider default -www -tls1_2

# In another terminal, connect as client — a successful handshake confirms TPM TLS works
openssl s_client -connect 127.0.0.1:8443 -servername tpm-tls.local -tls1_2

# If you see "cannot duplicate context" / "out of memory for object contexts":
# flush stale TPM handles, then restart s_server
tpm2_flushcontext -t
tpm2_flushcontext -l
tpm2_flushcontext -s
```