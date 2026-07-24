# 第一周实验：从源码编译内核并用QEMU启动

这是一份可以从头复现的实验手册，只记录学习内容、操作步骤、观察结果和问题分析。

## 1. 本周学习目标

完成实验后，应当能够：

1. 说明为什么选择维护中的LTS内核；
2. 从源码生成内核配置并完成编译；
3. 区分`vmlinux`和`bzImage`；
4. 说明内核镜像与initramfs的关系；
5. 使用系统安装的BusyBox制作最小initramfs；
6. 理解QEMU启动参数，并进入自己构建的Linux shell；
7. 修改内核版本字符串并通过`uname -r`验证；
8. 理解为什么构建和启动过程需要脚本化。

本周不学习GDB、内核模块和oops定位，这些内容放在第二周。

## 2. 实验环境

本次实验使用：

- 宿主机架构：x86_64；
- 目标内核：Linux 6.12.96 LTS；
- 编译器：GCC；
- 虚拟机：QEMU x86_64；
- 用户空间：Ubuntu软件包提供的静态BusyBox；
- 版本管理：独立Git仓库；
- 加速方式：TCG，因为当前没有可用的`/dev/kvm`。

TCG是QEMU的软件CPU模拟器。没有KVM会降低启动速度，但不影响本周实验结论。

## 3. 安装实验依赖

这里的GCC、QEMU、GDB、BusyBox等工具均使用发行版软件包，不从源码安装。
Linux内核本身是本周的学习对象，所以仍然需要下载内核源码进行编译。

Ubuntu/Debian执行：

```bash
sudo apt update
sudo apt install build-essential git qemu-system-x86 gdb cpio bison flex bc libssl-dev libelf-dev busybox-static
```

各软件的用途：

| 软件包            | 用途                           |
| ----------------- | ------------------------------ |
| `build-essential` | 提供GCC、Make等基本编译工具    |
| `git`             | 管理实验代码和记录             |
| `qemu-system-x86` | 模拟x86_64计算机并启动内核     |
| `gdb`             | 第二周调试`vmlinux`            |
| `cpio`            | 把rootfs打包为initramfs        |
| `bison`、`flex`   | 生成Kconfig解析器              |
| `bc`              | 内核构建脚本使用的计算工具     |
| `libssl-dev`      | 内核证书和加密相关构建依赖     |
| `libelf-dev`      | ELF、objtool等构建依赖         |
| `busybox-static`  | 为最小rootfs提供静态用户态命令 |

进入仓库并检查环境：

```bash
cd kernel-study
./scripts/check-env.sh
```

预期最后看到：

```text
Environment check passed.
```

### 3.1 BusyBox简介

BusyBox把许多常用Unix命令整合到一个可执行文件中，常用于嵌入式Linux、安装环境和initramfs。它提供的每个命令称为applet，例如`sh`、`ls`、`mount`、`cat`和`poweroff`。执行`busybox ls`时，BusyBox会运行内置的`ls` applet；通过名为`ls`的硬链接或符号链接调用同一个可执行文件时，BusyBox也会根据调用名称选择对应的applet。

本实验选择BusyBox的原因：

- 单个可执行文件即可提供shell和大部分基础命令，能够显著简化initramfs；
- `busybox --install`可以批量创建applet链接，不需要逐个复制命令；
- 静态链接版本不依赖客体中的动态链接器和共享库；
- 功能足以完成挂载`devtmpfs`、`procfs`、`sysfs`、运行交互式shell和关闭系统等启动实验。

BusyBox不是完整GNU用户空间的替代品。它的命令选项通常少于GNU coreutils，不同构建配置启用的applet也可能不同。实验脚本只使用当前`busybox-static`软件包已经提供的功能。

查看BusyBox版本和已启用的applet：

```bash
busybox | sed -n '1,12p'
busybox --list
```

单独确认BusyBox是静态链接程序：

```bash
command -v busybox
file "$(command -v busybox)"
```

输出中必须包含：

```text
statically linked
```

为什么必须静态链接：动态程序启动时还需要动态链接器和共享库。静态BusyBox把所需代码放入一个可执行文件，制作最小rootfs时不需要继续复制宿主机的`libc.so`和动态链接器。

### 3.2 cpio简介

`cpio`既是归档工具，也是一组归档格式。它能把目录、普通文件、符号链接、设备节点及其权限等元数据保存到一个连续归档中。Linux内核使用`cpio`归档表示initramfs，因此不能直接用普通tar归档代替。

本实验采用内核支持的`newc`格式。`file`通常将这种格式识别为：

```text
ASCII cpio archive (SVR4 with no CRC)
```

其中`no CRC`不是错误，只表示归档没有使用cpio的CRC变体。`newc`的文件头使用ASCII字段，魔数是`070701`。

`cpio`只负责归档，不负责压缩。完整的制作过程是：

```text
rootfs目录
→ find生成文件列表
→ cpio创建newc归档
→ gzip压缩
→ initramfs.cpio.gz
→ 内核解压并执行/init
```

等价的手工打包命令如下：

```bash
cd rootfs
find . -print0 \
    | cpio --null -o --format=newc \
    | gzip -9 > ../initramfs.cpio.gz
cd ..
```

各参数的作用：

- `find . -print0`使用空字符分隔文件名，避免文件名中的空格被错误拆分；
- `cpio --null`读取空字符分隔的文件名；
- `-o`表示创建归档，即copy-out；
- `--format=newc`选择Linux initramfs常用的`newc`格式；
- `gzip -9`压缩cpio归档，减小镜像体积。

查看压缩归档中的文件而不解包：

```bash
gzip -dc initramfs.cpio.gz | cpio -t
```

解包到临时目录：

```bash
mkdir extracted
cd extracted
gzip -dc ../initramfs.cpio.gz | cpio -idmv
```

其中`-i`表示提取归档，即copy-in；`-d`创建所需目录；`-m`保留修改时间；`-v`显示处理的文件名。cpio会保留文件权限，因此打包前必须保证`/init`可执行，否则内核解包后无法启动它：

```bash
chmod 755 rootfs/init
```

现代发行版中名为`initrd.img`的文件通常也是一个或多个cpio归档，可能包含未压缩的early cpio以及经过gzip、zstd等算法压缩的主initramfs。Ubuntu/Debian可以使用`lsinitramfs`查看、使用`unmkinitramfs`完整解包。

## 4. 认识实验目录

```text
kernel-study/
├── linux/             # Linux内核源码和编译产物，不提交Git
├── rootfs-overlay/    # 放入initramfs的自定义文件
├── modules/           # 后续内核模块
├── scripts/           # 环境检查、构建和启动脚本
├── labs/              # 实验代码
├── notes/             # 学习和实验过程
├── configs/           # 保存的构建配置
└── build/             # initramfs等生成物，不提交Git
```

源码和大型编译产物不提交Git。仓库只保存能够重现实验的配置、脚本、代码和笔记。

## 5. 下载Linux 6.12 LTS源码

从kernel.org下载固定版本，避免使用含义会随时间变化的文件名：

```bash
wget -O linux-6.12.96.tar.xz https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.96.tar.xz
```

先检查压缩包能否完整解码，再解压：

```bash
xz --test linux-6.12.96.tar.xz
tar -xf linux-6.12.96.tar.xz
mv linux-6.12.96 linux
```

`xz --test`没有输出且退出状态为0，表示压缩数据结构完整。它不能代替PGP签名验证；首次入门实验先记录这个边界，后续再增加源码签名验证。

确认源码版本：

```bash
make -s -C linux kernelversion
```

预期输出：

```text
6.12.96
```

## 6. 生成和修改内核配置

先使用x86_64默认配置：

```bash
make -C linux x86_64_defconfig
```

生成结果是`linux/.config`。不要直接手写整个`.config`，因为配置项之间存在依赖关系。

为实验内核增加版本后缀：

```bash
linux/scripts/config --file linux/.config \
    --set-str LOCALVERSION '-kernel-study'
```

为第二周GDB调试提前保留DWARF调试信息：

```bash
linux/scripts/config --file linux/.config --enable DEBUG_INFO
linux/scripts/config --file linux/.config --enable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
linux/scripts/config --file linux/.config --enable GDB_SCRIPTS
```

关闭KASLR，使第二周调试时内核虚拟地址保持稳定：

```bash
linux/scripts/config --file linux/.config --disable RANDOMIZE_BASE
```

根据依赖关系补全配置并保存副本：

```bash
make -C linux olddefconfig
mkdir -p configs
cp linux/.config configs/linux-6.12.96-x86_64.config
```

检查关键配置：

```bash
grep -E 'CONFIG_LOCALVERSION|CONFIG_DEBUG_INFO|CONFIG_GDB_SCRIPTS|CONFIG_RANDOMIZE_BASE' linux/.config
```

需要关注：

- `CONFIG_LOCALVERSION="-kernel-study"`；
- `CONFIG_DEBUG_INFO=y`；
- `CONFIG_GDB_SCRIPTS=y`；
- `CONFIG_RANDOMIZE_BASE`未启用。

## 7. 第一次编译内核

使用16个并行任务编译：

```bash
make -C linux -j16
```

`-j16`不是固定要求。可以通过`nproc`查看CPU逻辑线程数，再根据可用内存选择并行数。并行数过大会增加内存压力。

成功时末尾应出现：

```text
Kernel: arch/x86/boot/bzImage is ready
```

检查两个主要产物：

```bash
file linux/vmlinux
file linux/arch/x86/boot/bzImage
ls -lh linux/vmlinux linux/arch/x86/boot/bzImage
```

本次观察：

- `vmlinux`是约371 MiB的ELF文件，包含`debug_info`；
- `bzImage`是约13 MiB的x86可启动内核镜像；
- 版本字符串是`6.12.96-kernel-study`。

二者区别：

- `vmlinux`是链接后的ELF内核，保留符号、段信息和DWARF调试信息，主要供GDB、`nm`、`objdump`等工具分析；
- `arch/x86/boot/bzImage`包含x86启动代码和压缩后的内核，由bootloader或QEMU的`-kernel`加载；
- `bzImage`中的`bz`历史上表示big zImage，不表示bzip2。

## 8. 理解最小initramfs

内核本身不提供shell、`ls`、`mount`等用户态命令。内核完成初始化后必须启动第一个用户态进程。本实验通过initramfs提供：

- `/init`：第一个用户态进程，也就是PID 1；
- `/bin/busybox`：shell和常用命令；
- `/dev`、`/proc`、`/sys`、`/tmp`：运行时目录。

查看自定义`/init`：

```bash
sed -n '1,160p' rootfs-overlay/init
```

重点理解：

```sh
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
exec setsid cttyhack sh
```

- devtmpfs提供内核创建的设备节点，例如`/dev/console`；
- procfs提供进程和内核运行状态，例如`/proc/cmdline`；
- sysfs展示设备、驱动、总线等内核对象；
- `exec`让shell替换脚本进程，继续承担PID 1；
- `setsid cttyhack`为shell建立可交互的控制终端。

## 9. 制作initramfs

执行：

```bash
./scripts/build-rootfs.sh
```

脚本会：

1. 查找系统安装的`busybox`；
2. 验证它是静态链接程序；
3. 创建临时rootfs；
4. 安装BusyBox命令链接；
5. 复制`rootfs-overlay/init`；
6. 使用`cpio`的`newc`格式打包；
7. 使用gzip压缩；
8. 输出`build/initramfs.cpio.gz`；
9. 删除临时目录。

查看产物：

```bash
file build/initramfs.cpio.gz
ls -lh build/initramfs.cpio.gz
```

查看包内文件但不解压：

```bash
gzip -dc build/initramfs.cpio.gz | cpio -t | sed -n '1,40p'
```

应该能找到`/init`、`bin/busybox`以及BusyBox命令链接。

## 10. 使用QEMU启动

先阅读启动脚本：

```bash
sed -n '1,200p' scripts/run-qemu.sh
```

主要参数：

| 参数                 | 含义                             |
| -------------------- | -------------------------------- |
| `-machine accel=tcg` | 使用软件CPU模拟                  |
| `-m 512M`            | 给客体分配512 MiB内存            |
| `-smp 2`             | 提供两个虚拟CPU                  |
| `-kernel`            | 指定`bzImage`                    |
| `-initrd`            | 指定initramfs                    |
| `-append`            | 传递内核命令行                   |
| `console=ttyS0`      | 把内核控制台连接到第一个串口     |
| `rdinit=/init`       | 指定initramfs中的PID 1           |
| `-nographic`         | 不创建图形窗口，串口复用当前终端 |
| `-no-reboot`         | 内核重启时让QEMU退出             |

启动：

```bash
./scripts/run-qemu.sh
```

看到以下内容说明已经进入自己构建的系统：

```text
Linux kernel study lab is ready
Kernel: 6.12.96-kernel-study
PID 1:  1
```

在客体shell中亲手执行：

```sh
uname -r
cat /proc/cmdline
ps
mount
ls -l /init /bin/busybox
```

观察目标：

1. `uname -r`包含`-kernel-study`；
2. `/proc/cmdline`包含`console=ttyS0 rdinit=/init`；
3. `ps`中PID 1是当前shell；
4. `mount`中存在devtmpfs、procfs和sysfs；
5. `/init`和`/bin/busybox`都来自initramfs。

退出QEMU：按`Ctrl+A`，松开后再按`X`。

## 11. 自动启动测试

手工实验完成后可以运行自动验收：

```bash
KERNEL_ARGS='kernel-study.test=1' ./scripts/run-qemu.sh
```

`/init`检测到测试参数后打印：

```text
BOOT_TEST_OK
```

随后调用`poweroff -f`。本次实际验证结果：

```text
Linux kernel study lab is ready
Kernel: 6.12.96-kernel-study
PID 1:  1
BOOT_TEST_OK
reboot: Power down
```

这证明`bzImage`、initramfs、串口控制台和PID 1初始化路径能够配合工作。

## 12. 增量编译实验

第一次编译已经生成大部分目标文件。再次执行：

```bash
time make -C linux -j16
```

如果源码和配置未变化，Make会发现大部分目标已经是最新状态，耗时明显少于第一次全量编译。

然后只修改版本后缀：

```bash
linux/scripts/config --file linux/.config \
    --set-str LOCALVERSION '-kernel-study-v2'
make -C linux olddefconfig
time make -C linux -j16
```

重新构建initramfs并启动：

```bash
./scripts/build-rootfs.sh
./scripts/run-qemu.sh
```

进入shell后检查：

```sh
uname -r
```

应看到`6.12.96-kernel-study-v2`。实验完成后把版本恢复为`-kernel-study`并重新编译，避免后续记录出现两个基线版本。

## 13. 本周验收

不要只背答案，应结合刚才运行过的命令回答：

1. `vmlinux`和`bzImage`在文件格式、用途和大小上有什么区别？
   - 答：`vmlinux`是内核链接产生的未压缩ELF文件，包含符号、段信息和DWARF调试信息，主要用于GDB、`nm`和`objdump`等工具分析；本次构建约371 MiB。`bzImage`是包含x86启动代码和压缩内核负载的可启动镜像，主要由bootloader或QEMU加载；本次构建约13 MiB。
2. 为什么QEMU的`-kernel`使用`bzImage`，而GDB使用`vmlinux`？
   - 答：QEMU的`-kernel`参数需要能够按照x86启动协议进入内核的可启动镜像，因此使用`bzImage`；GDB需要函数符号、段地址及源码行映射，因此使用包含ELF符号和DWARF调试信息的`vmlinux`。
3. 内核启动后为什么还需要initramfs？
   - 答：内核负责管理硬件和系统资源，但启动完成后仍需运行第一个用户态程序。initramfs提供`/init`、shell、基础命令和早期启动所需文件；发行版通常利用它加载存储驱动、解锁磁盘并挂载真正的rootfs，本实验则直接把它作为最小rootfs。
4. 为什么本实验选择静态BusyBox？
   - 答：静态BusyBox已经把所需库代码链接进可执行文件，因此initramfs不必额外提供动态链接器和共享库；一个文件还能提供shell及大量基础命令，可以显著简化最小rootfs的制作和排错。
5. `/init`为什么会成为PID 1？
   - 答：本实验通过内核参数`rdinit=/init`指定第一个用户态程序。内核完成自身初始化后执行`/init`，它作为创建的第一个用户态进程获得PID 1；脚本最后通过`exec`让shell替换自身，因此shell继续承担PID 1。
6. `console=ttyS0`与`-nographic`如何配合？
   - 答：`console=ttyS0`让内核把控制台输出和输入连接到客体的第一个串口；QEMU的`-nographic`关闭图形窗口，并把客体串口和QEMU monitor复用到宿主机当前终端，因此可以直接在终端观察启动日志并操作shell。
7. built-in驱动和`.ko`模块与initramfs有什么关系？
   - 答：built-in驱动已经链接进内核镜像，启动时不依赖initramfs提供模块文件。`.ko`是可加载模块，只有挂载真正rootfs之前必须使用的模块，例如根磁盘控制器或根文件系统驱动，才需要随模块依赖信息一起放入initramfs；其他模块可以保存在最终rootfs的`/lib/modules/<kernel-release>/`中。本实验所需驱动均为built-in，不需要在initramfs中放置`.ko`。
8. 没有`/dev/kvm`为什么仍然能够启动？
   - 答：`/dev/kvm`不可用意味着QEMU不能使用KVM硬件加速，但仍可使用TCG在软件中翻译和执行客体CPU指令。TCG速度较慢，但不影响内核启动和本周实验结论。
9. 为什么要保存`.config`，但不提交整个内核源码和编译产物？
   - 答：`.config`记录启用的内核功能，是重建实验内核的关键输入。固定版本的内核源码可以从上游重新获取，编译产物体积大且能够重新生成，所以不提交它们。严格复现还需要记录源码版本、工具链、构建命令和构建环境，不能只依赖`.config`。
10. 为什么可重复构建对后续制造oops和调试很重要？
    - 答：可重复构建能够保持源码、配置、工具链、内核镜像和符号文件一致，使故障可以再次触发，并保证oops中的地址和符号能够对应到正确的`vmlinux`及源码位置；实验破坏环境后也能快速恢复到已知基线。

## 14. 实验结束时应保留的产物

- `configs/linux-6.12.96-x86_64.config`；
- `rootfs-overlay/init`；
- `scripts/check-env.sh`；
- `scripts/build-rootfs.sh`；
- `scripts/run-qemu.sh`；
- 本实验记录；
- 一个能够说明本周成果的Git commit。
