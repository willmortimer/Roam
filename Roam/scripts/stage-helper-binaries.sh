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

build_helper() {
    target="$1"

    if [ "${auto_build_helpers}" = "NO" ]; then
        return 1
    fi

    if ! command -v cross >/dev/null 2>&1; then
        log "cross not installed; skipping automatic helper build for ${target}"
        return 1
    fi

    log "building roam-helper for ${target} via cross"
    (
        cd "${rust_workspace}"
        cross build --release --target "${target}" --bin roam-helper
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
