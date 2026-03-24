#!/usr/bin/env bash
# roam-helper install script
# Downloads and installs the roam-helper binary for the current platform.
# Usage: curl -fsSL <url>/helper-install.sh | bash
#   or:  ./helper-install.sh [path-to-binary]

set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
BINARY_NAME="roam-helper"
INSTALL_PATH="${INSTALL_DIR}/${BINARY_NAME}"

# Detect architecture
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "${arch}" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            echo "Error: Unsupported architecture: ${arch}" >&2
            exit 1
            ;;
    esac
}

# Detect OS
detect_os() {
    local os
    os="$(uname -s)"
    case "${os}" in
        Linux)
            echo "linux"
            ;;
        *)
            echo "Error: Unsupported OS: ${os}. roam-helper only runs on Linux." >&2
            exit 1
            ;;
    esac
}

main() {
    local arch os binary_source

    arch="$(detect_arch)"
    os="$(detect_os)"

    echo "Detected platform: ${os}-${arch}"

    # If a binary path is provided as argument, use it directly
    if [ $# -ge 1 ] && [ -f "$1" ]; then
        binary_source="$1"
        echo "Installing from: ${binary_source}"
    else
        # Look for binary in standard locations
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local target="${arch}-unknown-${os}-musl"
        local candidates=(
            "${script_dir}/../target/${target}/release/${BINARY_NAME}"
            "${script_dir}/${BINARY_NAME}-${os}-${arch}"
            "./${BINARY_NAME}"
        )

        binary_source=""
        for candidate in "${candidates[@]}"; do
            if [ -f "${candidate}" ]; then
                binary_source="${candidate}"
                break
            fi
        done

        if [ -z "${binary_source}" ]; then
            echo "Error: Could not find ${BINARY_NAME} binary." >&2
            echo "Build it first with: cross build --release --target ${target}" >&2
            echo "Or provide the path: $0 /path/to/${BINARY_NAME}" >&2
            exit 1
        fi
        echo "Found binary: ${binary_source}"
    fi

    # Create install directory
    mkdir -p "${INSTALL_DIR}"

    # Install
    cp "${binary_source}" "${INSTALL_PATH}"
    chmod +x "${INSTALL_PATH}"

    # Verify
    if "${INSTALL_PATH}" version >/dev/null 2>&1; then
        local version
        version="$("${INSTALL_PATH}" version 2>&1 || true)"
        echo "Successfully installed ${BINARY_NAME} to ${INSTALL_PATH}"
        echo "Version: ${version}"
    else
        echo "Warning: Binary installed but failed version check." >&2
        echo "Installed to: ${INSTALL_PATH}" >&2
    fi

    # Check if install dir is in PATH
    if ! echo "${PATH}" | tr ':' '\n' | grep -q "^${INSTALL_DIR}$"; then
        echo ""
        echo "Note: ${INSTALL_DIR} is not in your PATH."
        echo "Add this to your shell profile:"
        echo "  export PATH=\"\${HOME}/.local/bin:\${PATH}\""
    fi
}

main "$@"
