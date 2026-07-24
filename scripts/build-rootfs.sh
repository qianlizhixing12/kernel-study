#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
overlay_dir="${project_dir}/rootfs-overlay"
image_path="${project_dir}/build/initramfs.cpio.gz"
busybox_path="$(command -v busybox || true)"

if [[ -z "${busybox_path}" ]]; then
    echo 'BusyBox 未安装。Ubuntu/Debian 请执行：' >&2
    echo 'sudo apt install busybox-static' >&2
    exit 1
fi

if ! file "${busybox_path}" | grep -q 'statically linked'; then
    echo "BusyBox 不是静态链接版本：${busybox_path}" >&2
    echo 'Ubuntu/Debian 请执行：sudo apt install busybox-static' >&2
    exit 1
fi

mkdir -p "${project_dir}/build"
staging_dir="$(mktemp -d "${project_dir}/build/rootfs.XXXXXX")"
trap 'rm -rf "${staging_dir}"' EXIT

mkdir -p \
    "${staging_dir}/bin" \
    "${staging_dir}/dev" \
    "${staging_dir}/proc" \
    "${staging_dir}/sys" \
    "${staging_dir}/tmp"
cp "${busybox_path}" "${staging_dir}/bin/busybox"
"${staging_dir}/bin/busybox" --install "${staging_dir}/bin"
cp -a "${overlay_dir}/." "${staging_dir}/"
chmod +x "${staging_dir}/init"

(
    cd "${staging_dir}"
    find . -print0 \
        | cpio --null --create --format=newc --quiet \
        | gzip -9 >"${image_path}"
)

echo "Created ${image_path}"
