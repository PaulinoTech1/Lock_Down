# SSH

Purpose: control remote shell access to the workstation so it cannot become a silent entry point. The default posture for this single-user workstation is SSH server DISABLED.

Status: RECOMMENDED (disabled by default; enabled only if a real need exists). Confidence: High.

## Default: disabled

- The OpenSSH server (`sshd`) is not installed or not enabled by default. No listening port, no attack surface.
- Verification: `systemctl is-enabled ssh` should report disabled (or the unit absent), and `ss -tlnp` should show no listener on port 22.
- If you do not need inbound SSH, stop here.

## If SSH must be enabled

Enable it deliberately for a bounded purpose (e.g. remote admin during a known travel window) and return to disabled afterward. Every setting below is explained.

### sshd_config snippet

```text
# sshd_config fragment for a single-user hardened workstation.
# Place in /etc/ssh/sshd_config.d/ as e.g. 90-hardened.conf, then
# 'sshd -t' to validate syntax before restarting the service.

# Do not listen on all interfaces; bind only where needed.
# Example: ListenAddress 192.168.1.10
Port 22

# Public-key authentication only. Password auth is off so credential
# stuffing and password guessing cannot reach an account.
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no

# Root may never log in over SSH, key or otherwise.
PermitRootLogin no

# Only the named account may connect. Replace with the actual username
# at deployment time; do not leave a placeholder in production.
AllowUsers <username>

# Prefer FIDO2-backed keys: generate client keys with
#   ssh-keygen -t ed25519-sk -O resident -O verify-required
# and add the public key to ~/.ssh/authorized_keys.
# ed25519-sk binds the private key material to the YubiKey and
# 'verify-required' demands the touch on each use.
PubkeyAuthentication yes

# Slow down online guessing even for keys.
MaxAuthTries 3
LoginGraceTime 60
MaxSessions 2

# No tunneling or forwarding unless the specific task needs it.
AllowTcpForwarding no
X11Forwarding no
PermitTunnel no

# Reduce information leakage.
Banner /etc/issue.net
PrintMotd no
```

### Why each control matters

- `PasswordAuthentication no`: removes the entire password-guessing class of attacks, including lateral movement with reused passwords.
- `PermitRootLogin no`: even a leaked root credential cannot authenticate remotely; escalation must happen locally through the pam_u2f-protected `sudo` path.
- `AllowUsers <username>`: fails closed for every other account, including future accounts and service accounts.
- `ed25519-sk`: hardware-backed keys mean a stolen `~/.ssh` directory is not enough; the private key material cannot leave the token.
- `MaxAuthTries 3`: bounds the guessing rate per connection before the server drops it.

### Rate limiting and firewall restriction

- Server-side: `MaxAuthTries` and `LoginGraceTime` above. Optional: `fail2ban` with an sshd jail for persistent scanners. This is OPTIONAL, not required, and only if the service stays enabled.
- Firewall-side: nftables should restrict port 22 to the specific source networks that need it (see docs/FIREWALL.md). Never expose SSH to the whole internet from a workstation unless there is a documented reason, and even then keep the source restriction.

## Limitations

- Disabling sshd protects the listener only; it does nothing about the SSH client config or agent forwarding habits on outbound connections.
- Public-key-only auth is only as strong as key handling: protect `~/.ssh` permissions (700 / 600) and keep the YubiKey resident keys registered.
- fail2ban adds log-parsing complexity; it is a rate-limit aid, not a security boundary.

## Recovery

- If locked out of a remote session, physical console access remains. The PAM policy (docs/YUBIKEY_PAM.md) still applies at the TTY and SDDM.
- Test the config with `sshd -t` before every restart; a syntax error on restart can drop the only remote path.
