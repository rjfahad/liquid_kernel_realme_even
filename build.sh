#!/bin/bash
#
# build.sh — Kernel Builder for Realme Even (MT6768)
# Supports: ReSukiSU only
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ─── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
header(){ echo -e "\n${CYAN}${BOLD}═══ $* ═══${NC}\n"; }

# ─── Config ──────────────────────────────────────────────────────────
PROTON_DIR="$SCRIPT_DIR/prebuilts-clang-proton"
PROTON_REPO="https://github.com/kdrag0n/proton-clang.git"
ANYKERNEL_DIR="$SCRIPT_DIR/anykernel3"
ANYKERNEL_REPO="https://github.com/osm0sis/AnyKernel3.git"
DEFCONFIG="even_defconfig"
ARCH="arm64"
JOBS="$(nproc)"
OUT_DIR="$SCRIPT_DIR/out"
RESUKISU_DIR="$SCRIPT_DIR/ReSukiSU"
RESUKISU_REPO="https://github.com/ReSukiSU/ReSukiSU.git"
ZIP_PREFIX="Liquid-Even-RUI2-ReSukiSU"
BUILD_VERSION_FILE="$SCRIPT_DIR/.kernel_zip_version"

read_build_version() {
    local version="1.0"

    if [ -f "$BUILD_VERSION_FILE" ]; then
        version="$(tr -d '[:space:]' < "$BUILD_VERSION_FILE" | head -n1)"
    fi

    if [[ "$version" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$version"
    else
        echo "1.0"
    fi
}

save_build_version() {
    printf '%s\n' "$1" > "$BUILD_VERSION_FILE"
}

zip_name_for_version() {
    echo "${ZIP_PREFIX}-v${1}.zip"
}

bump_build_version() {
    local version="$1"
    local major minor

    major="${version%%.*}"
    minor="${version#*.}"

    if [ "$major" = "$version" ]; then
        major="$version"
        minor="0"
    fi

    if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$minor" =~ ^[0-9]+$ ]]; then
        echo "$major.$((minor + 1))"
    else
        echo "1.0"
    fi
}

# ─── Detect root solution ───────────────────────────────────────────
detect_root_solution() {
    if [ -d "$RESUKISU_DIR" ]; then
        local remote
        remote="$(git -C "$RESUKISU_DIR" remote get-url origin 2>/dev/null || true)"
        if echo "$remote" | grep -qi "ReSukiSU"; then
            echo "resukisu"
            return
        fi
    fi

    if [ ! -d "$RESUKISU_DIR" ]; then
        echo "none"
        return
    fi

    echo "unknown"
}
# ─── Detect compiler ─────────────────────────────────────────────────
detect_compiler() {
    if [ -d "$PROTON_DIR" ] && [ -f "$PROTON_DIR/bin/clang" ]; then
        echo "proton"
    else
        echo "system"
    fi
}

# ─── Setup PATH ──────────────────────────────────────────────────────
setup_path() {
    if [ "$(detect_compiler)" = "proton" ]; then
        export PATH="$PROTON_DIR/bin:$PATH"
        # Prevent Proton's cross-ld from overriding host ld
        if [ -f "$PROTON_DIR/bin/ld" ] && [ ! -f "$PROTON_DIR/bin/ld.bak" ]; then
            mv "$PROTON_DIR/bin/ld" "$PROTON_DIR/bin/ld.bak"
            info "Renamed Proton ld → ld.bak"
        fi
    fi
}

# ─── Menu ────────────────────────────────────────────────────────────
show_menu() {
    local root_sol
    root_sol="$(detect_root_solution)"
    local compiler
    compiler="$(detect_compiler)"
    local build_version
    build_version="$(read_build_version)"

    header "Realme Even Kernel Builder"
    echo -e "  Compiler:   ${BOLD}${compiler}${NC}"
    echo -e "  Root:       ${BOLD}${root_sol}${NC}"
    echo -e "  Zip Ver:    ${BOLD}v${build_version}${NC}"
    echo -e "  Branch:     ${BOLD}$(git branch --show-current 2>/dev/null || echo 'detached')${NC}"
    echo ""
    echo "  [1] Setup Workspace"
    echo "  [2] Install ReSukiSU"
    echo "  [3] Build & Package"
    echo "  [4] Push to Device"
    echo "  [5] Clean"
    echo "  [0] Exit"
    echo ""
}

# ─── 1. Setup Workspace ─────────────────────────────────────────────
setup_workspace() {
    header "Setup Workspace"

    # Proton Clang
    if [ -d "$PROTON_DIR" ]; then
        info "Proton Clang already exists at $PROTON_DIR"
    else
        info "Cloning Proton Clang..."
        git clone --depth=1 "$PROTON_REPO" "$PROTON_DIR"
        # Fix ld.bak
        if [ -f "$PROTON_DIR/bin/ld" ]; then
            mv "$PROTON_DIR/bin/ld" "$PROTON_DIR/bin/ld.bak"
            info "Renamed Proton ld → ld.bak"
        fi
        info "Proton Clang installed"
    fi

    # AnyKernel3
    if [ -d "$ANYKERNEL_DIR" ]; then
        info "AnyKernel3 already exists at $ANYKERNEL_DIR"
    else
        info "Cloning AnyKernel3..."
        git clone --depth=1 "$ANYKERNEL_REPO" "$ANYKERNEL_DIR"
        info "AnyKernel3 installed"
    fi

    # Verify toolchain
    setup_path
    if command -v clang &>/dev/null; then
        local ver
        ver="$(clang --version | head -1)"
        info "Compiler: $ver"
    else
        error "clang not found in PATH"
    fi

    info "Workspace setup complete"
}

install_resukisu() {
    warn "ReSukiSU has known 4.14 compatibility issues:"
    warn "  - Missing syscall_fn_t for ARM64"
    warn "  - Missing strncpy_from_user_nofault"
    warn "  - Missing linux/pgtable.h"
    echo ""
    read -rp "  Continue anyway? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        return
    fi

    info "Installing ReSukiSU..."

    # Remove existing if present
    if [ -d "$RESUKISU_DIR" ]; then
        rm -rf "$RESUKISU_DIR"
    fi

    # Clone ReSukiSU
    git clone --depth=1 "$RESUKISU_REPO" "$RESUKISU_DIR"

    # Run setup
    cd "$SCRIPT_DIR"
    bash ReSukiSU/kernel/setup.sh main

    # Apply 4.14 compat fixes
    apply_resukisu_compat_fixes

    info "ReSukiSU installed (with 4.14 compat patches)"
    info "Make sure CONFIG_KSU=y is in defconfig"
}

apply_resukisu_compat_fixes() {
    info "Applying ReSukiSU compatibility patches..."

    local HOOK_DIR="$SCRIPT_DIR/drivers/kernelsu/hook"
    local FEAT_DIR="$SCRIPT_DIR/drivers/kernelsu/feature"
    local INIT_C="$SCRIPT_DIR/drivers/kernelsu/core/init.c"

    # Fix syscall_hook.h — add ARM64 typedef
    if [ -f "$HOOK_DIR/syscall_hook.h" ]; then
        if ! grep -q "defined(__aarch64__)" "$HOOK_DIR/syscall_hook.h"; then
            sed -i '/#if defined(__x86_64__)/a\#elif defined(__aarch64__)\ntypedef void *syscall_fn_t;' \
                "$HOOK_DIR/syscall_hook.h"
            info "Patched syscall_hook.h for ARM64"
        fi
    fi

    # Fix sucompat.c — pgtable.h → asm/pgtable.h
    if [ -f "$FEAT_DIR/sucompat.c" ]; then
        sed -i 's|#include <linux/pgtable.h>|#include <asm/pgtable.h>|' "$FEAT_DIR/sucompat.c"
        info "Patched sucompat.c pgtable include"
    fi

    # Fix init.c — MODULE_IMPORT_NS for 4.14
    if [ -f "$INIT_C" ]; then
        if grep -q "MODULE_IMPORT_NS" "$INIT_C" && ! grep -q "KERNEL_VERSION(5, 10" "$INIT_C"; then
            sed -i '/MODULE_IMPORT_NS(VFS_internal/a\#endif' "$INIT_C"
            sed -i '/MODULE_IMPORT_NS(VFS_internal/i\#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)' "$INIT_C"
            info "Patched init.c MODULE_IMPORT_NS"
        fi
    fi

    info "ReSukiSU compat patches applied"
}

# ─── 3. Build & Package ─────────────────────────────────────────────
build_and_package() {
    header "Build & Package"

    local root_sol
    root_sol="$(detect_root_solution)"
    local compiler
    compiler="$(detect_compiler)"
    local build_version
    build_version="$(read_build_version)"
    local zip_name
    zip_name="$(zip_name_for_version "$build_version")"
    local output_path="$SCRIPT_DIR/$zip_name"

    if [ "$compiler" = "system" ]; then
        error "No compiler found. Run Setup Workspace first."
        return
    fi

    setup_path

    info "Root solution: $root_sol"
    info "Compiler: Proton Clang 13.0.0"
    info "Output: $zip_name"
    echo ""

    if [ -f "$output_path" ]; then
        warn "Version v${build_version} already exists: $zip_name"
        while true; do
            read -rp "  [v] bump version  [o] overwrite  [c] cancel: " version_choice
            case "$version_choice" in
                v|V)
                    while :; do
                        build_version="$(bump_build_version "$build_version")"
                        zip_name="$(zip_name_for_version "$build_version")"
                        output_path="$SCRIPT_DIR/$zip_name"
                        if [ ! -f "$output_path" ]; then
                            break
                        fi
                    done
                    info "Using version v${build_version}"
                    info "Output: $zip_name"
                    break
                    ;;
                o|O)
                    rm -f "$output_path"
                    info "Overwriting existing zip"
                    break
                    ;;
                c|C)
                    return 0
                    ;;
                *)
                    warn "Please choose v, o, or c."
                    ;;
            esac
        done
    fi

    if [ ! -f "$OUT_DIR/.config" ]; then
        info "Generating defconfig..."
        make O=out ARCH=$ARCH CC=clang HOSTCC=clang CROSS_COMPILE=aarch64-linux-gnu- "$DEFCONFIG"
    else
        info "Using existing out/.config for incremental build"
    fi

    # Build
    info "Building kernel with $JOBS jobs..."
    local start_time
    start_time=$(date +%s)

    if ! make O=out ARCH=$ARCH CC=clang HOSTCC=clang CROSS_COMPILE=aarch64-linux-gnu- \
        -j"$JOBS" Image.gz-dtb; then
        error "Build failed!"
        return 1
    fi

    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    local kernel_size
    kernel_size="$(ls -lh "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" | awk '{print $5}')"

    info "Build complete in ${elapsed}s"
    info "Kernel: $OUT_DIR/arch/arm64/boot/Image.gz-dtb ($kernel_size)"

    # Package with AnyKernel3
    package_zip "$zip_name"
    save_build_version "$build_version"
}

package_zip() {
    local zip_name="${1:-Liquid-Even-RUI2.zip}"

    header "Packaging $zip_name"

    if [ ! -f "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" ]; then
        error "Image.gz-dtb not found. Build first."
        return 1
    fi

    if [ ! -d "$ANYKERNEL_DIR" ]; then
        warn "AnyKernel3 not found. Cloning..."
        git clone --depth=1 "$ANYKERNEL_REPO" "$ANYKERNEL_DIR"
    fi

    # Copy kernel
    cp "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" "$ANYKERNEL_DIR/Image.gz-dtb"

    # Update anykernel.sh kernel.string
    local root_sol
    root_sol="$(detect_root_solution)"
    local kernel_str="Liquid Kernel Even (ReSukiSU) by rjfahad"

    sed -i "s/^kernel.string=.*/kernel.string=$kernel_str/" "$ANYKERNEL_DIR/anykernel.sh"

    # Create zip
    local output_path="$SCRIPT_DIR/$zip_name"
    rm -f "$output_path"
    cd "$ANYKERNEL_DIR"
    zip -r9 "$output_path" . \
        -x ".git/*" \
        -x ".github/*" \
        -x "README.md" \
        -x "LICENSE" \
        2>/dev/null
    cd "$SCRIPT_DIR"

    local zip_size
    zip_size="$(ls -lh "$output_path" | awk '{print $5}')"
    info "Flashable zip: $output_path ($zip_size)"
}

# ─── 4. Push to Device ──────────────────────────────────────────────
push_to_device() {
    header "Push to Device"

    if ! adb devices | grep -q "device$"; then
        error "No device connected"
        return 1
    fi

    local build_version
    build_version="$(read_build_version)"
    local zip_name
    zip_name="$(zip_name_for_version "$build_version")"

    local zip_path="$SCRIPT_DIR/$zip_name"
    if [ ! -f "$zip_path" ]; then
        error "$zip_name not found. Build & Package first."
        return 1
    fi

    info "Pushing $zip_name to /sdcard/..."
    adb push "$zip_path" /sdcard/
    info "Done. Flash from recovery."
}

# ─── 5. Clean ────────────────────────────────────────────────────────
clean_all() {
    header "Clean"

    info "Removing out/..."
    rm -rf "$OUT_DIR"

    info "Removing *.zip..."
    rm -f "$SCRIPT_DIR"/${ZIP_PREFIX}*.zip

    info "Removing build version file..."
    rm -f "$BUILD_VERSION_FILE"

    info "Removing anykernel3/Image.gz-dtb..."
    rm -f "$ANYKERNEL_DIR/Image.gz-dtb" 2>/dev/null

    info "Clean complete"
}

# ─── Main ────────────────────────────────────────────────────────────
main() {
    while true; do
        show_menu
        read -rp "  > " choice
        case "$choice" in
            1) setup_workspace ;;
            2) install_resukisu ;;
            3) build_and_package ;;
            4) push_to_device ;;
            5) clean_all ;;
            0) exit 0 ;;
            *) error "Invalid choice" ;;
        esac
        echo ""
        read -rp "  Press Enter to continue..."
    done
}

main "$@"
