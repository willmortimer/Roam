#!/usr/bin/env bash
# roam-helper upgrade script
# Checks the installed version and upgrades if a newer binary is available.
# Usage: ./helper-upgrade.sh [path-to-new-binary]

set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
BINARY_NAME="roam-helper"
INSTALL_PATH="${INSTALL_DIR}/${BINARY_NAME}"

get_version() {
    local binary="$1"
    if [ -f "${binary}" ] && [ -x "${binary}" ]; then
        "${binary}" version 2>/dev/null | head -1 || echo "unknown"
    else
        echo "not installed"
    fi
}

main() {
    if [ $# -lt 1 ] || [ ! -f "$1" ]; then
        echo "Usage: $0 <path-to-new-binary>"
        exit 1
    fi

    local new_binary="$1"
    local current_version new_version

    current_version="$(get_version "${INSTALL_PATH}")"
    new_version="$(get_version "${new_binary}")"

    echo "Current version: ${current_version}"
    echo "New version:     ${new_version}"

    if [ "${current_version}" = "${new_version}" ]; then
        echo "Already up to date."
        exit 0
    fi

    # Backup current binary
    if [ -f "${INSTALL_PATH}" ]; then
        cp "${INSTALL_PATH}" "${INSTALL_PATH}.bak"
        echo "Backed up current binary to ${INSTALL_PATH}.bak"
    fi

    # Install new binary
    mkdir -p "${INSTALL_DIR}"
    cp "${new_binary}" "${INSTALL_PATH}"
    chmod +x "${INSTALL_PATH}"

    # Verify
    if "${INSTALL_PATH}" version >/dev/null 2>&1; then
        echo "Successfully upgraded to: $(get_version "${INSTALL_PATH}")"
        # Remove backup on success
        rm -f "${INSTALL_PATH}.bak"
    else
        echo "Error: New binary failed verification. Rolling back." >&2
        if [ -f "${INSTALL_PATH}.bak" ]; then
            mv "${INSTALL_PATH}.bak" "${INSTALL_PATH}"
            echo "Rolled back to previous version."
        fi
        exit 1
    fi
}

main "$@"
