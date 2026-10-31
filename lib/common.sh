# shellcheck shell=bash
# KookaBoot common helpers: logging, errors, prompts, dependency checks.

# shellcheck disable=SC2034  # used by other modules
KB_VERSION="1.1.0"

# Colours only when stderr is a terminal.
if [[ -t 2 ]]; then
    KB_C_RED=$'\e[31m'; KB_C_YEL=$'\e[33m'; KB_C_GRN=$'\e[32m'; KB_C_OFF=$'\e[0m'
else
    KB_C_RED=""; KB_C_YEL=""; KB_C_GRN=""; KB_C_OFF=""
fi

kb_info() { printf '%s\n' "$*" >&2; }
kb_ok()   { printf '%sOK%s    %s\n' "$KB_C_GRN" "$KB_C_OFF" "$*" >&2; }
kb_warn() { printf '%sWARN%s  %s\n' "$KB_C_YEL" "$KB_C_OFF" "$*" >&2; }
kb_err()  { printf '%sERROR%s %s\n' "$KB_C_RED" "$KB_C_OFF" "$*" >&2; }
kb_die()  { kb_err "$*"; exit 1; }

kb_need_root() {
    [[ ${KB_SKIP_ROOT_CHECK:-0} == 1 ]] && return 0
    [[ $(id -u) -eq 0 ]] || kb_die "This command must run as root (use sudo)."
}

# kb_need_cmd CMD [PACKAGE-HINT]
kb_need_cmd() {
    command -v "$1" >/dev/null 2>&1 || kb_die "Missing command '$1'. Install: ${2:-$1}"
}

kb_have_cmd() { command -v "$1" >/dev/null 2>&1; }

# kb_confirm_typed EXPECTED PROMPT
# The user must type EXPECTED exactly. Reads from stdin.
kb_confirm_typed() {
    local expected=$1 prompt=$2 answer
    printf '%s\nType "%s" to continue, anything else to cancel: ' "$prompt" "$expected" >&2
    IFS= read -r answer || answer=""
    [[ $answer == "$expected" ]] || kb_die "Cancelled. Nothing was changed."
}

# kb_human BYTES -> e.g. "3.2 GiB"
kb_human() {
    awk -v b="$1" 'BEGIN{
        split("B KiB MiB GiB TiB",u," "); i=1
        while (b>=1024 && i<5) { b/=1024; i++ }
        if (i==1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
    }'
}

# kb_version_ge A B -> true if version A >= B
kb_version_ge() {
    [[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1) == "$2" ]]
}
