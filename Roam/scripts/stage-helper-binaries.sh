#!/bin/sh

set -eu

log() {
    echo "[helper-stage] $*"
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
srcroot_dir=${SRCROOT:-$(CDPATH= cd -- "${script_dir}/.." && pwd)}
repo_root=$(CDPATH= cd -- "${srcroot_dir}/.." && pwd)
rust_workspace="${repo_root}/roam-rs"
source_helpers_dir="${srcroot_dir}/Roam/Resources/Helpers"
bundle_helpers_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Helpers"
auto_build_helpers=${ROAM_AUTO_BUILD_HELPERS:-YES}

mkdir -p "${bundle_helpers_dir}"

asset_arch_name() {
    case "$1" in
        x86_64-unknown-linux-musl) printf "x86_64" ;;
        aarch64-unknown-linux-musl) printf "aarch64" ;;
        *) return 1 ;;
    esac
}

copy_stage_binary() {
    src="$1"
    target="$2"
    arch_name="$3"
    canonical_dest="${bundle_helpers_dir}/roam-helper-${target}"
    release_dest="${bundle_helpers_dir}/roam-helper-linux-${arch_name}"

    cp "${src}" "${canonical_dest}"
    chmod +x "${canonical_dest}"
    cp "${canonical_dest}" "${release_dest}"
    chmod +x "${release_dest}"
    log "staged ${target} from ${src}"
}

resolve_cross_binary() {
    if command -v mise >/dev/null 2>&1; then
        if cross_path=$(cd "${repo_root}" && mise which cross 2>/dev/null); then
            printf "%s\n" "${cross_path}"
            return 0
        fi
    fi

    if command -v cross >/dev/null 2>&1; then
        command -v cross
        return 0
    fi

    return 1
}

has_cross_host_toolchain() {
    rustup toolchain list 2>/dev/null | rg -q '^stable-x86_64-unknown-linux-gnu'
}

run_cross_build() {
    cross_bin="$1"
    target="$2"

    clean_env() {
        env -i \
            HOME="${HOME:-}" \
            PATH="${PATH:-}" \
            USER="${USER:-}" \
            LOGNAME="${LOGNAME:-${USER:-}}" \
            SHELL="${SHELL:-/bin/sh}" \
            TMPDIR="${TMPDIR:-/tmp}" \
            CARGO_HOME="${CARGO_HOME:-${HOME:-}/.cargo}" \
            RUSTUP_HOME="${RUSTUP_HOME:-${HOME:-}/.rustup}" \
            RUSTUP_TOOLCHAIN="stable" \
            DOCKER_HOST="${DOCKER_HOST:-}" \
            CONTAINER_HOST="${CONTAINER_HOST:-}" \
            COLIMA_HOME="${COLIMA_HOME:-}" \
            XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
            SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-}" \
            "$@"
    }

    if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || printf "0")" = "1" ] && [ -x /usr/bin/arch ]; then
        clean_env /usr/bin/arch -arm64 "${cross_bin}" build --release --target "${target}" --bin roam-helper
        return $?
    fi

    clean_env "${cross_bin}" build --release --target "${target}" --bin roam-helper
}

build_helper() {
    target="$1"
    cross_bin=""
    is_apple_silicon_host=0

    if [ "${auto_build_helpers}" = "NO" ]; then
        return 1
    fi

    if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || printf "0")" = "1" ]; then
        is_apple_silicon_host=1
    fi

    if ! cross_bin=$(resolve_cross_binary); then
        log "cross not installed; skipping automatic helper build for ${target}"
        return 1
    fi

    if [ "${is_apple_silicon_host}" = "1" ] && ! has_cross_host_toolchain; then
        log "missing rustup toolchain stable-x86_64-unknown-linux-gnu; run 'just cross-host-toolchain' once"
        return 1
    fi

    if [ "${is_apple_silicon_host}" = "1" ] && [ "${target}" = "aarch64-unknown-linux-musl" ]; then
        log "skipping automatic aarch64 helper build on Apple Silicon; provide a prebuilt artifact for this target"
        return 1
    fi

    case "${cross_bin}" in
        *"/.local/share/mise/"*)
            log "building roam-helper for ${target} via mise-managed cross"
            ;;
        *)
            log "building roam-helper for ${target} via cross"
            ;;
    esac

    (
        cd "${rust_workspace}"
        run_cross_build "${cross_bin}" "${target}"
    )
}

stage_target() {
    target="$1"
    arch_name=$(asset_arch_name "${target}")

    canonical_name="roam-helper-${target}"
    release_asset_name="roam-helper-linux-${arch_name}"
    release_target_path="${rust_workspace}/target/${target}/release/roam-helper"

    candidates="
${source_helpers_dir}/${canonical_name}
${source_helpers_dir}/${release_asset_name}
${release_target_path}
${rust_workspace}/target/${target}/debug/roam-helper
${rust_workspace}/scripts/${release_asset_name}
"

    old_ifs=$IFS
    IFS='
'
    for candidate in ${candidates}; do
        if [ -f "${candidate}" ]; then
            copy_stage_binary "${candidate}" "${target}" "${arch_name}"
            IFS=$old_ifs
            return 0
        fi
    done
    IFS=$old_ifs

    if build_helper "${target}" && [ -f "${release_target_path}" ]; then
        copy_stage_binary "${release_target_path}" "${target}" "${arch_name}"
        return 0
    fi

    log "no helper artifact available for ${target}"
    return 1
}

log "preparing remote helper binaries"

stage_target "x86_64-unknown-linux-musl" || true
stage_target "aarch64-unknown-linux-musl" || true

log "helper staging complete"
