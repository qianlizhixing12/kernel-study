#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kernel_image="${project_dir}/linux/arch/x86/boot/bzImage"
initramfs_image="${project_dir}/build/initramfs.cpio.gz"

if [[ ! -f "${kernel_image}" ]]; then
    echo "Kernel image not found: ${kernel_image}" >&2
    exit 1
fi

if [[ ! -f "${initramfs_image}" ]]; then
    echo "Initramfs image not found: ${initramfs_image}" >&2
    exit 1
fi

extra_kernel_args="${KERNEL_ARGS:-}"

exec qemu-system-x86_64 \
    -machine accel=tcg \
    -m 512M \
    -smp 2 \
    -kernel "${kernel_image}" \
    -initrd "${initramfs_image}" \
    -append "console=ttyS0 rdinit=/init panic=-1 ${extra_kernel_args}" \
    -nographic \
    -no-reboot

