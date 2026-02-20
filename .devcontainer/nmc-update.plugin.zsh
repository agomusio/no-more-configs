# nmc-update — Oh My Zsh plugin for No More Configs update notifications
# Installed to ~/.oh-my-zsh/custom/plugins/nmc-update/nmc-update.plugin.zsh
#
# On shell open:
# 1. Shows a banner if an update is available (flag file exists)
# 2. Kicks off a background check if ≥24h since the last one

_NMC_WORKSPACE="${CLAUDE_WORKSPACE:-/workspace}"
_NMC_CACHE_DIR="${HOME}/.cache/nmc"
_NMC_FLAG_FILE="${_NMC_CACHE_DIR}/.update-available"
_NMC_CHECK_FILE="${_NMC_CACHE_DIR}/.last-update-check"
_NMC_CHECK_INTERVAL=86400  # 24 hours in seconds

# ---------------------------------------------------------------------------
# Banner — print if an update is available
# ---------------------------------------------------------------------------

_nmc_update_banner() {
    [[ -f "$_NMC_FLAG_FILE" ]] || return

    local new_version
    new_version=$(<"$_NMC_FLAG_FILE")
    [[ -z "$new_version" ]] && return

    # Read current version from CHANGELOG.md
    local current_version=""
    if [[ -f "${_NMC_WORKSPACE}/CHANGELOG.md" ]]; then
        current_version=$(sed -n 's/^## \[\([0-9]*\.[0-9]*\.[0-9]*\)\].*/\1/p' "${_NMC_WORKSPACE}/CHANGELOG.md" | head -1)
    fi

    # Don't show banner if versions match (already updated)
    if [[ -n "$current_version" && "$current_version" == "$new_version" ]]; then
        rm -f "$_NMC_FLAG_FILE"
        return
    fi

    print -P ""
    if [[ -n "$current_version" ]]; then
        print -P "%F{cyan}%B[nmc]%b%f Update available: %F{yellow}v${current_version}%f → %F{green}%Bv${new_version}%b%f. Run %F{cyan}%Bnmc-update%b%f to update."
    else
        print -P "%F{cyan}%B[nmc]%b%f Update available: %F{green}%Bv${new_version}%b%f. Run %F{cyan}%Bnmc-update%b%f to update."
    fi
    print ""
    print ""
}

# ---------------------------------------------------------------------------
# Background check — fetch + compare, write flag file
# ---------------------------------------------------------------------------

_nmc_bg_check() {
    # Run in subshell so we don't affect the interactive shell
    (
        local workspace="$_NMC_WORKSPACE"
        local cache_dir="$_NMC_CACHE_DIR"
        local flag_file="$_NMC_FLAG_FILE"
        local check_file="$_NMC_CHECK_FILE"

        # Must be a git repo
        [[ -d "${workspace}/.git" ]] || return

        mkdir -p "$cache_dir"

        # Fetch quietly
        git -C "$workspace" fetch origin --quiet 2>/dev/null || return

        # Compare local HEAD vs remote
        local local_head remote_head
        local_head=$(git -C "$workspace" rev-parse HEAD 2>/dev/null) || return
        remote_head=$(git -C "$workspace" rev-parse origin/main 2>/dev/null) || return

        # Only notify when origin is ahead of local (not when local is ahead)
        local behind
        behind=$(git -C "$workspace" rev-list HEAD..origin/main --count 2>/dev/null) || return

        if [[ "$behind" -gt 0 ]]; then
            # Read the remote version from CHANGELOG.md
            local remote_version=""
            remote_version=$(git -C "$workspace" show origin/main:CHANGELOG.md 2>/dev/null \
                | sed -n 's/^## \[\([0-9]*\.[0-9]*\.[0-9]*\)\].*/\1/p' | head -1)

            if [[ -n "$remote_version" ]]; then
                echo "$remote_version" > "$flag_file"
            else
                echo "new" > "$flag_file"
            fi
        else
            # Up to date — clear any stale flag
            rm -f "$flag_file"
        fi

        # Record check timestamp
        date +%s > "$check_file"
    ) &!
}

# ---------------------------------------------------------------------------
# Plugin init
# ---------------------------------------------------------------------------

# 1. Show banner if flag file exists
_nmc_update_banner

# 2. Conditionally start background check
_nmc_should_check() {
    # No cache dir yet — first time
    [[ ! -f "$_NMC_CHECK_FILE" ]] && return 0

    local last_check now elapsed
    last_check=$(<"$_NMC_CHECK_FILE")
    now=$(date +%s)
    elapsed=$(( now - last_check ))

    (( elapsed >= _NMC_CHECK_INTERVAL ))
}

if _nmc_should_check; then
    _nmc_bg_check
fi
