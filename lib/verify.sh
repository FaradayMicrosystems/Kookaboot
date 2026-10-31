# shellcheck shell=bash
# Image verification: SHA-256 and optional GPG signature of the checksum file.

# kb_sha256 FILE -> lowercase hex digest
kb_sha256() {
    sha256sum -- "$1" | awk '{print tolower($1)}'
}

# kb_sums_lookup SUMSFILE NAME -> expected SHA-256 for NAME, or nothing.
# Understands GNU style ("HASH  name", "HASH *name") and BSD style
# ("SHA256 (name) = HASH"), including PGP clear-signed files (Fedora).
kb_sums_lookup() {
    local sums=$1 name=$2
    awk -v n="$name" '
        # BSD style
        $1=="SHA256" && $2=="(" n ")" && $3=="=" { print tolower($4); exit }
        # GNU style
        length($1)==64 && $1 ~ /^[0-9A-Fa-f]+$/ {
            f=$2; sub(/^\*/, "", f); sub(/^\.\//, "", f)
            if (f==n) { print tolower($1); exit }
        }
    ' "$sums"
}

# kb_verify_signature SUMSFILE SIGFILE|"" KEYRING
# SIGFILE empty = SUMSFILE is clear-signed. Uses gpgv so only KEYRING is trusted.
kb_verify_signature() {
    local sums=$1 sig=$2 keyring=$3
    kb_need_cmd gpgv "gnupg (gpgv)"
    [[ -r $keyring ]] || kb_die "Keyring not readable: $keyring"
    keyring=$(readlink -f -- "$keyring")
    if [[ -n $sig ]]; then
        gpgv --keyring "$keyring" -- "$sig" "$sums" >/dev/null 2>&1
    else
        gpgv --keyring "$keyring" -- "$sums" >/dev/null 2>&1
    fi
}

# kb_verify_image FILE EXPECTED_HASH -> 0 if match
kb_verify_image() {
    local file=$1 expected actual
    expected=$(tr 'A-F' 'a-f' <<<"$2")
    [[ $expected =~ ^[0-9a-f]{64}$ ]] || kb_die "Not a valid SHA-256 value: $2"
    actual=$(kb_sha256 "$file")
    if [[ $actual == "$expected" ]]; then
        return 0
    fi
    kb_err "Checksum mismatch for $(basename -- "$file")"
    kb_err "  expected $expected"
    kb_err "  actual   $actual"
    return 1
}

# kb_resolve_expected ISO SHA256 SUMS SIG KEYRING -> prints the expected hash.
# Exactly one of SHA256 or SUMS must be given.
kb_resolve_expected() {
    local iso=$1 hash=$2 sums=$3 sig=$4 keyring=$5 name
    if [[ -n $hash && -n $sums ]]; then
        kb_die "Give --sha256 or --sums, not both."
    fi
    if [[ -n $hash ]]; then
        kb_warn "Using a checksum you typed. It is only as trustworthy as where you copied it from."
        printf '%s\n' "$hash"
        return 0
    fi
    [[ -n $sums ]] || kb_die "No checksum given. Use --sha256 HASH or --sums FILE."
    [[ -r $sums ]] || kb_die "Checksum file not readable: $sums"

    if [[ -n $keyring ]]; then
        if kb_verify_signature "$sums" "$sig" "$keyring"; then
            kb_ok "Signature on $(basename -- "$sums") is valid."
        else
            kb_die "Signature check FAILED for $(basename -- "$sums"). Do not use this image."
        fi
    elif [[ -n $sig ]]; then
        kb_die "--sig needs --keyring (the distro's public key file)."
    else
        kb_warn "Checksum file is not signature-checked (no --keyring given)."
    fi

    name=$(basename -- "$iso")
    hash=$(kb_sums_lookup "$sums" "$name")
    [[ -n $hash ]] || kb_die "$name is not listed in $(basename -- "$sums")."
    printf '%s\n' "$hash"
}
