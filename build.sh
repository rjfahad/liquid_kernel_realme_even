#!/bin/bash
#
# build.sh — Kernel Builder for Realme Even (MT6768)
# Supports: KernelSU v0.9.5, KernelSU-Next, and ReSukiSU
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
KSU_REPO="https://github.com/tiann/KernelSU.git"
KSU_NEXT_REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"
SUKISU_REPO="https://github.com/SukiSU-Ultra/SukiSU-Ultra.git"

# ─── Detect root solution ───────────────────────────────────────────
detect_root_solution() {
    local remote
    if [ -d "$SCRIPT_DIR/KernelSU-Next" ]; then
        remote="$(git -C "$SCRIPT_DIR/KernelSU-Next" remote get-url origin 2>/dev/null || true)"
        if echo "$remote" | grep -qi "KernelSU-Next"; then
            echo "ksunext"
            return
        fi
    fi

    if [ -d "$SCRIPT_DIR/KernelSU" ]; then
        remote="$(git -C "$SCRIPT_DIR/KernelSU" remote get-url origin 2>/dev/null || true)"
        if echo "$remote" | grep -qi "SukiSU-Ultra"; then
            echo "sukisu"
            return
        elif echo "$remote" | grep -qi "tiann/KernelSU"; then
            echo "ksu"
            return
        fi
    fi

    if [ -d "$SCRIPT_DIR/ReSukiSU" ]; then
        remote="$(git -C "$SCRIPT_DIR/ReSukiSU" remote get-url origin 2>/dev/null || true)"
        if echo "$remote" | grep -qi "ReSukiSU"; then
            echo "resukisu"
            return
        fi
    fi

    if [ ! -d "$SCRIPT_DIR/KernelSU" ] && [ ! -d "$SCRIPT_DIR/KernelSU-Next" ] && [ ! -d "$SCRIPT_DIR/ReSukiSU" ]; then
        echo "none"
        return
    fi

    if echo "$remote" | grep -qi "SukiSU-Ultra"; then
        echo "sukisu"
    elif echo "$remote" | grep -qi "tiann/KernelSU"; then
        echo "ksu"
    else
        echo "unknown"
    fi
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

    header "Realme Even Kernel Builder"
    echo -e "  Compiler:   ${BOLD}${compiler}${NC}"
    echo -e "  Root:       ${BOLD}${root_sol}${NC}"
    echo -e "  Branch:     ${BOLD}$(git branch --show-current 2>/dev/null || echo 'detached')${NC}"
    echo ""
    echo "  [1] Setup Workspace"
    echo "  [2] Install Root Solution"
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

# ─── 2. Install Root Solution ───────────────────────────────────────
install_root() {
    header "Install Root Solution"

    local current
    current="$(detect_root_solution)"

    echo "  Current: ${BOLD}${current}${NC}"
    echo ""
    echo "  [a] KernelSU v0.9.5 (recommended for 4.14)"
    echo "  [b] KernelSU-Next (legacy)"
    echo "  [c] SukiSU-Ultra latest (⚠️  4.14 compat issues)"
    echo "  [d] Remove root (none)"
    echo "  [0] Back"
    echo ""
    read -rp "  > " choice

    case "$choice" in
        a|A)
            install_kernelsu
            ;;
        b|B)
            install_ksunext
            ;;
        c|C)
            install_sukisu
            ;;
        d|D)
            remove_root
            ;;
        0)
            return
            ;;
        *)
            error "Invalid choice"
            ;;
    esac
}

install_kernelsu() {
    info "Installing KernelSU v0.9.5..."

    # Remove existing if present
    if [ -d "$SCRIPT_DIR/KernelSU" ]; then
        rm -rf "$SCRIPT_DIR/KernelSU"
    fi

    # Clone KernelSU
    git clone --depth=1 -b v0.9.5 "$KSU_REPO" "$SCRIPT_DIR/KernelSU"

    # Run setup
    cd "$SCRIPT_DIR"
    bash KernelSU/kernel/setup.sh v0.9.5

    info "KernelSU v0.9.5 installed"
    info "Make sure CONFIG_KSU=y is in defconfig"
}

install_ksunext() {
    info "Installing KernelSU-Next (legacy)..."

    if [ -d "$SCRIPT_DIR/KernelSU-Next" ]; then
        rm -rf "$SCRIPT_DIR/KernelSU-Next"
    fi

    git clone --depth=1 -b legacy "$KSU_NEXT_REPO" "$SCRIPT_DIR/KernelSU-Next"

    cd "$SCRIPT_DIR"
    bash KernelSU-Next/kernel/setup.sh legacy 2>/dev/null || true

    apply_ksunext_compat_fixes

    info "KernelSU-Next installed"
    info "Make sure CONFIG_KSU=y and CONFIG_KSU_MANUAL_HOOK=y is in defconfig"
}

apply_ksunext_compat_fixes() {
    info "Applying KernelSU-Next compat fixes..."

    local INTEGRATION="$SCRIPT_DIR/KernelSU-Next/kernel/ksud_integration.c"
    local HIDE="$SCRIPT_DIR/KernelSU-Next/kernel/selinux/selinux_hide.c"

    if [ -f "$INTEGRATION" ] && grep -q "ksu_input_hook" "$INTEGRATION" && ! grep -q "__attribute__((weak))" "$INTEGRATION"; then
        sed -i 's/void ksu_input_hook(/__attribute__((weak)) void ksu_input_hook(/' "$INTEGRATION"
        info "Patched KernelSU-Next ksud_integration.c"
    fi

    if [ -f "$HIDE" ] && grep -q "ksu_input_hook" "$HIDE" && ! grep -q "__attribute__((weak))" "$HIDE"; then
        sed -i '/#include <linux\/uaccess.h>/i\extern void ksu_input_hook(char *buf, size_t size) __attribute__((weak));' "$HIDE"
        info "Patched KernelSU-Next selinux_hide.c"
    fi

    info "KernelSU-Next compat fixes applied"
}

install_sukisu() {
    warn "SukiSU-Ultra has known 4.14 compatibility issues:"
    warn "  - Missing syscall_fn_t for ARM64"
    warn "  - Missing strncpy_from_user_nofault"
    warn "  - Missing linux/pgtable.h"
    echo ""
    read -rp "  Continue anyway? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        return
    fi

    info "Installing SukiSU-Ultra..."

    # Remove existing if present
    if [ -d "$SCRIPT_DIR/KernelSU" ]; then
        rm -rf "$SCRIPT_DIR/KernelSU"
    fi

    # Clone SukiSU-Ultra
    git clone --depth=1 "$SUKISU_REPO" "$SCRIPT_DIR/KernelSU"

    # Run setup
    cd "$SCRIPT_DIR"
    bash KernelSU/kernel/setup.sh main

    # Apply 4.14 compat fixes
    apply_sukisu_compat_fixes

    info "SukiSU-Ultra installed (with 4.14 compat patches)"
    info "Make sure CONFIG_KSU=y is in defconfig"
}

apply_sukisu_compat_fixes() {
    info "Applying 4.14 compatibility patches..."

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

    info "Compat patches applied"
}

remove_root() {
    info "Removing root solution..."

    if [ -d "$SCRIPT_DIR/KernelSU" ]; then
        cd "$SCRIPT_DIR"
        bash KernelSU/kernel/setup.sh --cleanup 2>/dev/null || true
        rm -rf "$SCRIPT_DIR/KernelSU"
    fi

    if [ -d "$SCRIPT_DIR/KernelSU-Next" ]; then
        cd "$SCRIPT_DIR"
        bash KernelSU-Next/kernel/setup.sh --cleanup 2>/dev/null || true
        rm -rf "$SCRIPT_DIR/KernelSU-Next"
    fi

    info "Root solution removed"
}

# ─── 3. Build & Package ─────────────────────────────────────────────
build_and_package() {
    header "Build & Package"

    local root_sol
    root_sol="$(detect_root_solution)"
    local compiler
    compiler="$(detect_compiler)"

    if [ "$compiler" = "system" ]; then
        error "No compiler found. Run Setup Workspace first."
        return
    fi

    setup_path

    local zip_name
    case "$root_sol" in
        ksu)    zip_name="Liquid-Even-RUI2-KSU.zip" ;;
        ksunext) zip_name="Liquid-Even-RUI2-KSUNext.zip" ;;
        sukisu) zip_name="Liquid-Even-RUI2-SukiSU.zip" ;;
        resukisu) zip_name="Liquid-Even-RUI2-ReSukiSU.zip" ;;
        *)      zip_name="Liquid-Even-RUI2.zip" ;;
    esac

    info "Root solution: $root_sol"
    info "Compiler: Proton Clang 13.0.0"
    info "Output: $zip_name"
    echo ""

    # Clean
    info "Cleaning build artifacts..."
    make O=out ARCH=$ARCH CC=clang HOSTCC=clang CROSS_COMPILE=aarch64-linux-gnu- mrproper 2>/dev/null

    # Defconfig
    info "Generating defconfig..."
    make O=out ARCH=$ARCH CC=clang HOSTCC=clang CROSS_COMPILE=aarch64-linux-gnu- "$DEFCONFIG"

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
    local kernel_str
    case "$root_sol" in
        ksu)    kernel_str="Liquid Kernel Even (KSU) by rjfahad" ;;
        ksunext) kernel_str="Liquid Kernel Even (KSUNext) by rjfahad" ;;
        sukisu) kernel_str="Liquid Kernel Even (SukiSU) by rjfahad" ;;
        resukisu) kernel_str="Liquid Kernel Even (ReSukiSU) by rjfahad" ;;
        *)      kernel_str="Liquid Kernel Even by rjfahad" ;;
    esac

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

    local root_sol
    root_sol="$(detect_root_solution)"
    local zip_name
    case "$root_sol" in
        ksu)    zip_name="Liquid-Even-RUI2-KSU.zip" ;;
        ksunext) zip_name="Liquid-Even-RUI2-KSUNext.zip" ;;
        sukisu) zip_name="Liquid-Even-RUI2-SukiSU.zip" ;;
        resukisu) zip_name="Liquid-Even-RUI2-ReSukiSU.zip" ;;
        *)      zip_name="Liquid-Even-RUI2.zip" ;;
    esac

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
    rm -f "$SCRIPT_DIR"/Liquid-Even-RUI2*.zip

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
            2) install_root ;;
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
