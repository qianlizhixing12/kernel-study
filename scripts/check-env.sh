#!/usr/bin/env bash

set -u

required_tools=(
    gcc
    make
    git
    qemu-system-x86_64
    gdb
    cpio
    bison
    flex
    bc
    openssl
    busybox
)

missing_tools=()

for tool_name in "${required_tools[@]}"; do
    if command -v "${tool_name}" >/dev/null 2>&1; then
        printf 'OK   %-22s %s\n' \
            "${tool_name}" \
            "$("${tool_name}" --version 2>/dev/null | head -n 1)"
    else
        printf 'MISS %s\n' "${tool_name}"
        missing_tools+=("${tool_name}")
    fi
done

printf '\nCPU threads: %s\n' "$(nproc)"
free -h | awk '/Mem:/ {printf "Memory: %s total, %s available\n", $2, $7}'
df -h . | awk 'NR == 2 {printf "Disk: %s available\n", $4}'

if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    echo 'QEMU acceleration: KVM available'
else
    echo 'QEMU acceleration: KVM unavailable; use TCG'
fi

if ((${#missing_tools[@]} > 0)); then
    printf '\nMissing required tools: %s\n' "${missing_tools[*]}" >&2
    echo 'Ubuntu/Debian 可执行以下命令安装：' >&2
    echo 'sudo apt install build-essential git qemu-system-x86 gdb cpio bison flex bc libssl-dev libelf-dev busybox-static' >&2
    exit 1
fi

if ! file "$(command -v busybox)" | grep -q 'statically linked'; then
    echo 'BusyBox must be statically linked.' >&2
    echo 'Ubuntu/Debian 请安装：sudo apt install busybox-static' >&2
    exit 1
fi

echo
echo 'Environment check passed.'
