#!/usr/bin/env python3
"""Extract session cookies from a Chromium-family browser into a Netscape cookie
jar for clip-link. macOS only (uses the login Keychain).

Usage:
    python3 extract-cookies.py \
        --profile "$HOME/Library/Application Support/Google/Chrome Dev/Default" \
        --keychain "Chrome Safe Storage" \
        --host substack.com --host pragmaticengineer.com \
        --out "$HOME/.config/clip-link/cookies.txt"

Notes for whoever runs this:
  * --profile is the exact profile dir. Chrome keeps one dir per signed-in
    account; map an email to its dir via the browser's "Local State" JSON
    (profile.info_cache[*].user_name), since "Default" is not always the one
    you want.
  * --keychain is the Keychain service holding the AES key. Chrome (all
    channels) uses "Chrome Safe Storage"; Chromium/Brave use their own. The
    first read triggers a macOS Keychain prompt the user must approve.
  * Cookies live in a SQLite DB with recent writes in a -wal/-journal sidecar;
    this copies the sidecars too so freshly-set logins aren't missed.
  * The jar is a credential. It is written chmod 600. Never copy it, or any
    cookie value, into a vault, repo, or model output.
"""
import argparse, hashlib, os, shutil, sqlite3, subprocess, sys, tempfile
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", required=True, help="browser profile directory")
    ap.add_argument("--keychain", default="Chrome Safe Storage")
    ap.add_argument("--host", action="append", default=[], help="domain suffix to include (repeatable)")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    pw = subprocess.check_output(
        ["security", "find-generic-password", "-w", "-s", args.keychain],
        stderr=subprocess.DEVNULL,
    ).strip()
    key = hashlib.pbkdf2_hmac("sha1", pw, b"saltysalt", 1003, 16)

    def decrypt(enc):
        if not enc or enc[:3] not in (b"v10", b"v11"):
            return None
        c = Cipher(algorithms.AES(key), modes.CBC(b" " * 16), backend=default_backend()).decryptor()
        pt = c.update(enc[3:]) + c.finalize()
        pt = pt[: -pt[-1]]              # strip PKCS7 padding
        for skip in (32, 0):           # modern Chrome prepends a 32-byte domain hash
            try:
                return pt[skip:].decode()
            except UnicodeDecodeError:
                continue
        return None

    tmp = tempfile.mkdtemp()
    db = os.path.join(tmp, "Cookies")
    src = os.path.join(args.profile, "Cookies")
    shutil.copy(src, db)
    for side in ("-wal", "-shm", "-journal"):
        if os.path.exists(src + side):
            shutil.copy(src + side, db + side)

    con = sqlite3.connect(db)
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    where = " OR ".join(["host_key LIKE ?"] * len(args.host)) or "1"
    params = ["%" + h for h in args.host]
    rows = con.execute(
        f"SELECT host_key,name,path,is_secure,expires_utc,encrypted_value FROM cookies WHERE {where}",
        params,
    ).fetchall()

    lines = ["# Netscape HTTP Cookie File", "# clip-link session jar\n"]
    n = 0
    for host, name, path, secure, exp, enc in rows:
        val = decrypt(enc)
        if val is None:
            continue
        expiry = int(exp / 1_000_000 - 11644473600) if exp else 0
        flag = "TRUE" if host.startswith(".") else "FALSE"
        lines.append("\t".join([host, flag, path, "TRUE" if secure else "FALSE", str(max(expiry, 0)), name, val]))
        n += 1

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(lines) + "\n")
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"wrote {n} cookies to {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
