# shellcheck shell=bash
# Ventoy: fetch the pinned, tested release and drive Ventoy2Disk.sh.

# Pinned release. Change only after the hardware test matrix passes.
KB_VENTOY_VERSION=${KB_VENTOY_VERSION:-1.1.18}
KB_VENTOY_SHA256=${KB_VENTOY_SHA256:-d86ff9de63d94c8b8f1f6b14d23c55af4b88e8207bf2893890892a6a97b1ad54}
KB_VENTOY_URL_BASE=${KB_VENTOY_URL_BASE:-https://github.com/ventoy/Ventoy/releases/download}
KB_CACHE_DIR=${KB_CACHE_DIR:-/var/cache/kookaboot}

# kb_ventoy_dir -> path to an extracted, verified Ventoy release.
# KB_VENTOY_DIR overrides (offline use, tests).
kb_ventoy_dir() {
    if [[ -n ${KB_VENTOY_DIR:-} ]]; then
        [[ -f $KB_VENTOY_DIR/Ventoy2Disk.sh ]] || kb_die "KB_VENTOY_DIR has no Ventoy2Disk.sh: $KB_VENTOY_DIR"
        printf '%s\n' "$KB_VENTOY_DIR"
        return 0
    fi

    local v=$KB_VENTOY_VERSION
    local tarball="ventoy-$v-linux.tar.gz"
    local dir="$KB_CACHE_DIR/ventoy-$v"

    if [[ -f $dir/Ventoy2Disk.sh ]]; then
        printf '%s\n' "$dir"
        return 0
    fi

    kb_need_cmd curl
    mkdir -p -- "$KB_CACHE_DIR"
    if [[ ! -f $KB_CACHE_DIR/$tarball ]]; then
        kb_info "Downloading Ventoy $v ..."
        curl -fL --retry 3 -o "$KB_CACHE_DIR/$tarball.part" "$KB_VENTOY_URL_BASE/v$v/$tarball" \
            || kb_die "Download failed: $KB_VENTOY_URL_BASE/v$v/$tarball"
        mv -- "$KB_CACHE_DIR/$tarball.part" "$KB_CACHE_DIR/$tarball"
    fi

    if ! kb_verify_image "$KB_CACHE_DIR/$tarball" "$KB_VENTOY_SHA256"; then
        rm -f -- "$KB_CACHE_DIR/$tarball"
        kb_die "Ventoy download failed its checksum and was deleted."
    fi
    kb_ok "Ventoy $v checksum verified."

    tar -xzf "$KB_CACHE_DIR/$tarball" -C "$KB_CACHE_DIR" || kb_die "Could not extract $tarball"
    [[ -f $dir/Ventoy2Disk.sh ]] || kb_die "Unexpected Ventoy archive layout."
    printf '%s\n' "$dir"
}

# kb_ventoy_run ARGS... -> runs Ventoy2Disk.sh, auto-answering its y/n prompts.
# KookaBoot has already asked the user for typed confirmation.
kb_ventoy_run() {
    local dir
    dir=$(kb_ventoy_dir) || exit 1
    ( cd -- "$dir" && printf 'y\ny\ny\n' | sh ./Ventoy2Disk.sh "$@" )
}

# kb_ventoy_disk_version DEV -> installed Ventoy version, or empty
kb_ventoy_disk_version() {
    kb_ventoy_run -l "$1" 2>/dev/null | awk -F': *' '/^Ventoy Version in Disk/ {print $2}'
}
