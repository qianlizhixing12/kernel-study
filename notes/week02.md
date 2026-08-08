# 第二周实验：GDB、内核模块与oops定位

本周在第一周可重复启动的实验环境上增加内核调试能力，编写并加载第一个内核模块，主动制造NULL pointer dereference，再使用日志、符号和源码完成定位。

所有崩溃实验只能在QEMU客体中执行，不在宿主机内核加载实验模块。

## 1. 本周学习目标

完成实验后，应当能够：

1. 说明`vmlinux`、`bzImage`和`.ko`的用途；
2. 说明built-in与module的构建、加载和生命周期差异；
3. 理解QEMU的`-s`、`-S`及GDB远程调试流程；
4. 使用GDB在`start_kernel()`及模块函数上设置断点；
5. 编写、编译、加载、查看和卸载基础内核模块；
6. 在QEMU中主动制造NULL pointer dereference；
7. 从oops中识别instruction pointer、call trace和taint；
8. 使用GDB、`addr2line`和源码定位故障行；
9. 恢复崩溃环境并证明正常模块仍可加载和卸载。

## 2. 准备理解的问题

开始实验前先记录自己的初始理解：

1. `vmlinux`为什么适合调试，而`bzImage`适合启动？
2. QEMU的`-s`与`-S`分别改变什么？
3. GDB如何把运行地址映射到函数名和源码行？
4. built-in代码与`.ko`模块分别在什么时候进入内核？
5. `module_init()`和`module_exit()`分别由谁调用？
6. 模块卸载时为什么必须先停止异步工作并释放资源？
7. oops与kernel panic有什么区别？
8. instruction pointer、call trace和taint分别说明什么？
9. 为什么模块地址不能直接按`vmlinux`中的地址解析？
10. 如何证明定位结果对应本次运行的内核和模块？

## 3. 时间安排

| 时间                 | 内容                                             | 产物                            |
| -------------------- | ------------------------------------------------ | ------------------------------- |
| 工作日第1次，1.5小时 | GDB基础、ELF符号、QEMU gdbstub、`-s`与`-S`       | GDB连接记录和启动断点截图或日志 |
| 工作日第2次，1.5小时 | 内核模块结构、Kbuild、加载和卸载                 | 可正常加载和卸载的模块          |
| 工作日第3次，1小时   | oops结构、instruction pointer、call trace和taint | oops字段说明                    |
| 周末，4～5小时       | 制造NULL pointer dereference并用三种方法定位     | 完整故障报告和修复验证          |

## 4. 实验基线检查

先确认第一周基线仍然可用：

```bash
./scripts/check-env.sh
make -s -C linux kernelrelease
file linux/vmlinux linux/arch/x86/boot/bzImage
KERNEL_ARGS='kernel-study.test=1' ./scripts/run-qemu.sh
```

预期内核版本为：

```text
6.12.96-kernel-study
```

确认调试和模块配置：

```bash
grep -E 'CONFIG_MODULES=|CONFIG_DEBUG_INFO=|CONFIG_GDB_SCRIPTS=|CONFIG_RANDOMIZE_BASE' linux/.config
```

需要确认：

- `CONFIG_MODULES=y`；
- `CONFIG_DEBUG_INFO=y`；
- `CONFIG_GDB_SCRIPTS=y`；
- `CONFIG_RANDOMIZE_BASE`未启用。

保存以下信息，后续定位时用于证明符号与运行内核匹配：

```bash
sha256sum linux/vmlinux linux/arch/x86/boot/bzImage
git rev-parse HEAD
gcc --version | sed -n '1p'
```

## 5. GDB连接QEMU

QEMU的gdbstub允许宿主机GDB远程调试客体：

- `-s`等价于`-gdb tcp::1234`，在TCP 1234端口等待GDB连接；
- `-S`让虚拟CPU上电后暂停，必须由GDB执行`continue`才开始运行。

本阶段需要给启动脚本增加可选调试参数，普通启动行为必须保持不变。调试启动应等价于：

```text
qemu-system-x86_64 ... -s -S
```

在终端一启动QEMU，使其暂停并等待GDB；在终端二执行：

```bash
gdb linux/vmlinux
```

进入GDB后执行：

```gdb
target remote :1234
break start_kernel
continue
```

命中断点后记录：

```gdb
info registers
bt
list
```

继续启动：

```gdb
continue
```

验收证据：

- GDB成功连接`localhost:1234`；
- `start_kernel()`断点命中；
- `bt`能够显示符号；
- `list`能够显示对应源码；
- 断开GDB后QEMU仍能正常启动或退出。

本次使用QEMU Unix socket提供gdbstub，实际命中结果：

```text
Thread 1 hit Breakpoint 1, start_kernel () at init/main.c:915
#0  start_kernel () at init/main.c:915
#1  x86_64_start_reservations (...) at arch/x86/kernel/head64.c:507
#2  x86_64_start_kernel (...) at arch/x86/kernel/head64.c:488
#3  secondary_startup_64 () at arch/x86/kernel/head_64.S:413
rip 0xffffffff8323d920 <start_kernel>
rsp 0xffffffff82a03f30
```

`list start_kernel`正确显示`init/main.c:913～919`，证明本次`vmlinux`的符号和源码映射可用。由于受限环境禁止TCP监听，本次使用`-gdb unix:/tmp/kernel-study-gdb.sock,server=on,wait=off -S`代替`-s -S`；两者只在传输端点上不同，调试流程相同。

## 6. 编写基础内核模块

模块目录使用一个顶层Kbuild文件统一组织，各子目录保留自己的Kbuild文件和源码：

```text
modules/
├── Makefile
├── hello/
│   ├── Makefile
│   └── hello.c
└── null-deref/
    ├── Makefile
    └── null-deref.c
```

顶层`modules/Makefile`通过`obj-m += <subdir>/`让Kbuild递归进入模块子目录，不使用普通`include`，避免子目录源码路径被错误地解释为相对于`modules/`。

模块至少包含：

- `MODULE_LICENSE("GPL")`；
- `module_init()`入口；
- `module_exit()`出口；
- 初始化和退出日志；
- 能够连续加载、卸载，不遗留资源。

使用当前内核构建树统一编译全部实验模块：

```bash
make -C linux M="$PWD/modules" modules
```

也可以只编译单个子目录：

```bash
make -C linux M="$PWD/modules/hello" modules
```

检查模块产物：

```bash
file modules/hello/hello.ko
modinfo modules/hello/hello.ko
file modules/null-deref/null-deref.ko
modinfo modules/null-deref/null-deref.ko
```

统一清理模块构建产物：

```bash
make -C linux M="$PWD/modules" clean
```

将模块放入initramfs后，重新构建并启动QEMU。在客体中执行：

```sh
insmod /modules/hello.ko
lsmod
dmesg | tail -20
rmmod hello
dmesg | tail -20
```

需要记录：

- `insmod`前后`lsmod`的变化；
- 初始化和退出函数的日志顺序；
- `rmmod`后模块是否消失；
- 重复加载和卸载10次是否成功。

## 7. built-in与module对比

回答并通过构建结果验证：

| 对比项       | built-in       | module                          |
| ------------ | -------------- | ------------------------------- |
| 构建产物     | 链接进内核镜像 | 独立`.ko`文件                   |
| 进入内核时间 | 随内核启动     | `insmod`或`modprobe`加载时      |
| 初始化入口   | 启动过程中调用 | 加载模块时调用                  |
| 卸载         | 不能单独卸载   | 无引用且允许卸载时可执行`rmmod` |
| 典型配置     | `CONFIG_FOO=y` | `CONFIG_FOO=m`                  |

需要理解：`.ko`不仅包含机器码，还包含ELF节、符号、重定位信息和模块元数据。加载器需要为模块分配内存、解析符号并完成重定位，因此模块运行地址不是链接进`vmlinux`的固定地址。

## 8. 制造NULL pointer oops

在`modules/null-deref/`中编写独立实验模块。模块默认必须安全，只有显式传入参数时才触发NULL pointer dereference，避免误加载即崩溃。

完成源码后从项目根目录统一编译，并重新生成包含最新`.ko`文件的initramfs：

```bash
make -C linux M="$PWD/modules" modules
./scripts/build-rootfs.sh
```

触发前先保存正常加载和卸载证据。随后在QEMU中加载故障模式：

```sh
insmod /modules/null-deref.ko trigger=1
```

为避免oops后继续运行造成二次破坏，启动故障实验时应传入：

```text
oops=panic panic=-1
```

预期QEMU停在panic现场，由宿主机退出或通过GDB检查状态。必须保存从错误类型开始到call trace结束的完整日志，不能只截取最后几行。

## 9. 阅读oops

按以下顺序分析日志：

1. 错误类型，例如`BUG: kernel NULL pointer dereference`；
2. 访问地址和访问类型；
3. instruction pointer，即发生异常时正在执行的指令；
4. 寄存器状态；
5. call trace，即到达故障点的调用路径；
6. 模块列表和故障函数所属模块；
7. taint状态；
8. panic是否由`oops=panic`触发。

形成最小调用路径：

```text
insmod /modules/null-deref.ko trigger=1
  [   46.815421] null_deref: loading out-of-tree module taints kernel.
  [   46.826688] null-deref loaded
  [   46.826788] null-deref NULL pointer dereference
  [   46.827347] BUG: kernel NULL pointer dereference, address: 0000000000000000
  [   46.827507] #PF: supervisor write access in kernel mode
  [   46.827567] #PF: error_code(0x0002) - not-present page
  [   46.827685] PGD 453f067 P4D 453f067 PUD 453e067 PMD 0
  [   46.827910] Oops: Oops: 0002 [#1] PREEMPT SMP NOPTI
  [   46.828267] CPU: 1 UID: 0 PID: 70 Comm: insmod Tainted: G           O       6.12.96-kernel-study #1
  [   46.828447] Tainted: [O]=OOT_MODULE
  [   46.828510] Hardware name: QEMU Ubuntu 26.04 PC (i440FX + PIIX, 1996), BIOS 1.17.0-debian-1.17.0-1ubuntu1 04/01/2014
  [   46.828741] RIP: 0010:null_deref_init+0x25/0xff0 [null_deref]
  [   46.829284] Code: 90 90 90 90 90 f3 0f 1e fa 48 c7 c7 00 40 00 a0 e8 20 10 f6 e1 83 3d e9 bf ff ff 00 74 17 48 c7 c7 30 40 00 a0 e8 0b 10 f6 e1 <c7> 04 25 00 00 00 00 01 00 00 00 31 c0 c3 cc cc cc cc 00
  00
  [   46.829627] RSP: 0018:ffffc9000021fd48 EFLAGS: 00010246
  [   46.829723] RAX: 0000000000000023 RBX: 0000000000000000 RCX: 0000000000000000
  [   46.829820] RDX: 0000000000000000 RSI: ffffc9000021fc00 RDI: 0000000000000001
  [   46.829917] RBP: ffff8880043bb5a0 R08: 00000000ffffdfff R09: ffffffff82b08928
  [   46.830022] R10: 0000000000000003 R11: 00000000ffffe000 R12: ffffffffa0006010
  [   46.830123] R13: ffffc9000021fd50 R14: 0000000036aca940 R15: 0000000000000000
  [   46.830297] FS:  0000000036ac63c0(0000) GS:ffff88801f500000(0000) knlGS:0000000000000000
  [   46.830448] CS:  0010 DS: 0000 ES: 0000 CR0: 0000000080050033
  [   46.830539] CR2: 0000000000000000 CR3: 0000000004508000 CR4: 00000000000006f0
  [   46.830722] Call Trace:
  [   46.831233]  <TASK>
  [   46.831357]  do_one_initcall+0x57/0x220
  [   46.832309]  do_init_module+0x5d/0x200
  [   46.832372]  init_module_from_file+0x81/0xc0
  [   46.832444]  idempotent_init_module+0x119/0x310
  [   46.832515]  __x64_sys_finit_module+0x51/0x90
  [   46.832578]  do_syscall_64+0x9e/0x1c0
  [   46.832646]  entry_SYSCALL_64_after_hwframe+0x77/0x7f
  [   46.832810] RIP: 0033:0x4e5eed
  [   46.832944] Code: ff c3 66 2e 0f 1f 84 00 00 00 00 00 90 f3 0f 1e fa 48 89 f8 48 89 f7 48 89 d6 48 89 ca 4d 89 c2 4d 89 c8 4c 8b 4c 24 08 0f 05 <48> 3d 01 f0 ff ff 73 01 c3 48 c7 c1 e8 ff ff ff f7 d8 64
  88
  [   46.833181] RSP: 002b:00007fffa706ce98 EFLAGS: 00000246 ORIG_RAX: 0000000000000139
  [   46.833336] RAX: ffffffffffffffda RBX: 0000000000000000 RCX: 00000000004e5eed
  [   46.833440] RDX: 0000000000000000 RSI: 0000000036aca940 RDI: 0000000000000003
  [   46.833534] RBP: 00007fffa706cef0 R08: 0000000000000006 R09: 0000000036ac7e0f
  [   46.833628] R10: 0000000000000000 R11: 0000000000000246 R12: 0000000036aca940
  [   46.833934] Modules linked in: null_deref(O+)
  [   46.834273] CR2: 0000000000000000
  [   46.834613] ---[ end trace 0000000000000000 ]---
  [   46.834753] RIP: 0010:null_deref_init+0x25/0xff0 [null_deref]
  [   46.834844] Code: 90 90 90 90 90 f3 0f 1e fa 48 c7 c7 00 40 00 a0 e8 20 10 f6 e1 83 3d e9 bf ff ff 00 74 17 48 c7 c7 30 40 00 a0 e8 0b 10 f6 e1 <c7> 04 25 00 00 00 00 01 00 00 00 31 c0 c3 cc cc cc cc 00
  00
  [   46.835130] RSP: 0018:ffffc9000021fd48 EFLAGS: 00010246
  [   46.835213] RAX: 0000000000000023 RBX: 0000000000000000 RCX: 0000000000000000
  [   46.835310] RDX: 0000000000000000 RSI: ffffc9000021fc00 RDI: 0000000000000001
  [   46.835409] RBP: ffff8880043bb5a0 R08: 00000000ffffdfff R09: ffffffff82b08928
  [   46.835504] R10: 0000000000000003 R11: 00000000ffffe000 R12: ffffffffa0006010
  [   46.835605] R13: ffffc9000021fd50 R14: 0000000036aca940 R15: 0000000000000000
  [   46.835699] FS:  0000000036ac63c0(0000) GS:ffff88801f500000(0000) knlGS:0000000000000000
  [   46.835812] CS:  0010 DS: 0000 ES: 0000 CR0: 0000000080050033
  [   46.835893] CR2: 0000000000000000 CR3: 0000000004508000 CR4: 00000000000006f0
  [   46.836161] Kernel panic - not syncing: Fatal exception
  [   46.836880] Kernel Offset: disabled
```

实际调用路径必须以本次日志为准，不能直接照抄上面的示意。

## 10. 使用符号定位故障

本次oops已经给出最关键的定位入口：

```text
RIP: 0010:null_deref_init+0x25/0xff0 [null_deref]
CR2: 0000000000000000
Code: ... <c7> 04 25 00 00 00 00 01 00 00 00 ...
```

它表示异常发生在`null_deref`模块的`null_deref_init()`函数内，instruction pointer位于函数入口之后`0x25`字节。`CR2=0`表示页故障访问的线性地址是NULL；`#PF: supervisor write access`表示内核态正在执行写操作。下面使用同一次构建生成的`null-deref.ko`进行三种交叉定位。

### 10.1 GDB

离线分析模块时直接把`.ko`作为GDB的符号文件：

```bash
gdb modules/null-deref/null-deref.ko
```

进入GDB后执行：

```gdb
info address null_deref_init
info line *(null_deref_init + 0x25)
list *(null_deref_init + 0x25)
x/4i null_deref_init + 0x25
```

本次实际结果：

```text
Symbol "null_deref_init" is a function at address 0x10.
Line 18 ... starts at address 0x35 <null_deref_init+37>
0x35 <null_deref_init+37>: movl $0x1,0x0
```

`0x25`是函数内偏移，不是`.ko`中的直接地址。模块ELF中的`null_deref_init`地址为`0x10`，所以目标地址是：

```text
0x10+0x25=0x35
```

如果连接QEMU进行在线调试，应先加载`linux/vmlinux`并连接gdbstub：

```gdb
target remote :1234
```

随后使用内核GDB脚本加载模块符号：

```gdb
lx-symbols
break null_deref_init
continue
```

也可以读取客体中的模块节地址，再手工使用`add-symbol-file`。模块包含`.init.text`、`.text`和`.data`等多个节，不能假设所有节都使用同一个基地址：

```sh
cat /sys/module/null_deref/sections/.init.text
cat /sys/module/null_deref/sections/.text
cat /sys/module/null_deref/sections/.data
```

`null_deref_init()`位于`.init.text`。手工加载时必须把对应节的实际地址传给GDB。模块每次加载的地址可能变化，因此不能复用上一次启动记录的绝对地址。

### 10.2 addr2line

先查看模块符号在ELF节内的地址：

```bash
nm -n modules/null-deref/null-deref.ko \
    | rg ' null_deref_init$'
```

本次输出为：

```text
0000000000000010 t null_deref_init
```

将符号地址`0x10`与oops提供的函数内偏移`0x25`相加，得到模块ELF中的地址`0x35`：

```bash
addr2line \
    -e modules/null-deref/null-deref.ko \
    -fip 0x35
```

本次定位结果：

```text
null_deref_init at modules/null-deref/null-deref.c:18
```

不能把日志中的模块运行时绝对地址直接交给`addr2line -e null-deref.ko`，因为`.ko`是可重定位ELF，加载器会在运行时为各节分配地址并执行重定位。对于日志已经打印出的`函数名+偏移`，使用“ELF符号地址+函数内偏移”即可进行离线定位。

### 10.3 objdump

只反汇编包含初始化函数的`.init.text`节，并同时显示源码和重定位信息：

```bash
objdump \
    -drS \
    --section=.init.text \
    modules/null-deref/null-deref.ko
```

本次在地址`0x35`看到：

```text
*ptr = 1;
35: c7 04 25 00 00 00 00 movl $0x1,0x0
3c: 01 00 00 00
```

机器码与oops中尖括号标记的故障指令一致：

```text
<c7> 04 25 00 00 00 00 01 00 00 00
```

`movl $0x1,0x0`尝试把立即数`1`写入地址`0`，与源码中的`*ptr = 1`、`CR2=0`及`supervisor write access`完全对应。

### 10.4 定位结论

三种方法得到相同结论：

```text
故障模块：null_deref
故障函数：null_deref_init
函数内偏移：0x25
模块ELF地址：0x35
源码位置：modules/null-deref/null-deref.c:18
对应指令：movl $0x1,0x0
访问类型：内核态写访问
访问地址：0x0
根因：ptr被初始化为NULL后执行*ptr = 1
```

## 11. 修复与回归验证

修复NULL指针问题后重新编译模块，并完成：

1. 正常加载；
2. 执行功能路径；
3. 正常卸载；
4. 重复加载和卸载10次；
5. `dmesg`中没有新的oops、warning或资源泄漏提示；
6. 第一周的自动启动测试仍然通过。

不能以删除故障触发代码作为唯一修复。应增加正确的指针初始化、输入检查或错误返回，并解释为什么修复后不会再到达非法访问。

本次按当周一个commit的记录方式保留注释形式的故障代码，活动代码将`ptr`初始化为局部变量`data`的有效地址。执行`*ptr = 1`时写入的是当前内核栈中的有效对象，不再访问地址`0`。

代码和构建检查：

```text
checkpatch：0 errors, 0 warnings
clang-format --dry-run --Werror：exit 0
make -C linux M="$PWD/modules" modules：成功
```

本次回归使用的构建标识：

```text
kernelrelease：6.12.96-kernel-study
vermagic：6.12.96-kernel-study SMP preempt mod_unload
vmlinux sha256：b069563343885c8fbe8cf300a5b57cb04bc4023442e40f334912ba3b5125f05a
bzImage sha256：f47fde81074d2528bb4bd8784d43877d94c7c7f748e51011528684d7c52e7021
null-deref.ko sha256：75f5c511e503a25ffd3169513ef31aa19f3e3ad3da3395f322f75ee331dc7aec
```

在QEMU客体中使用`trigger=1`连续加载和卸载10次，实际结果：

```text
MODULE_TEST_ROUND=1
...
MODULE_TEST_ROUND=10
MODULE_10_ROUNDS_OK
null-deref loaded
null-deref unloaded
```

10轮中每轮均出现一组`loaded`和`unloaded`日志，没有出现`BUG:`、`WARNING:`或`Kernel panic`。首次加载出现`[O]=OOT_MODULE` taint是加载out-of-tree模块的预期状态，不是回归失败。

第一周启动回归结果：

```text
Command line: console=ttyS0 rdinit=/init oops=panic panic=-1 kernel-study.test=1
Kernel: 6.12.96-kernel-study
PID 1: 1
BOOT_TEST_OK
reboot: Power down
boot_exit=0
```

## 12. 故障报告

按以下结构记录本次实验：

```text
现象：dmesg内核oops
复现步骤：insmod /modules/null-deref.ko trigger=1
关键日志：BUG: kernel NULL pointer dereference, address: 0000000000000000
instruction pointer：null_deref_init+0x25
故障机器码：<c7> 04 25 00 00 00 00 01 00 00 00 31 c0 c3 cc cc cc cc 00
call trace：
  [   46.831233]  <TASK>
  [   46.831357]  do_one_initcall+0x57/0x220
  [   46.832309]  do_init_module+0x5d/0x200
  [   46.832372]  init_module_from_file+0x81/0xc0
  [   46.832444]  idempotent_init_module+0x119/0x310
  [   46.832515]  __x64_sys_finit_module+0x51/0x90
  [   46.832578]  do_syscall_64+0x9e/0x1c0
  [   46.832646]  entry_SYSCALL_64_after_hwframe+0x77/0x7f
taint：[O]=OOT_MODULE
故障函数及偏移：null_deref_init+0x25
源码位置：modules/null-deref/null-deref.c:18
模块ELF地址：0x35
对应指令：movl $0x1,0x0
根因：访问空指针（写访问）
修复方法：指针初始化有效地址
验证方式：重新编译并打包模块；在QEMU中使用trigger=1连续加载卸载10次，每轮均正常输出loaded和unloaded，没有BUG、WARNING或Kernel panic；第一周BOOT_TEST_OK回归通过
为什么原测试没有发现：故障是实验故意加入的trigger=1分支；此前正常路径只使用默认trigger=0，没有覆盖NULL写入分支
```

## 13. 本周验收问题

1. `vmlinux`与`bzImage`为什么用途不同？
   - 答：`vmlinux`是内核链接产生的未压缩ELF文件，包含符号、段信息和DWARF调试信息，主要用于GDB、`nm`和`objdump`等工具分析；错误的vmlinux会导致符号地址、源码行、结构体布局和调用栈解析错误。`bzImage`是包含x86启动代码和压缩内核负载的可启动镜像，主要由bootloader或QEMU加载。
2. QEMU的`-s`与`-S`分别做什么？
   - 答：`-s`等价于`-gdb tcp::1234`，在TCP 1234端口等待GDB连接。`-S`让虚拟CPU上电后暂停，必须由GDB执行`continue`才开始运行。
3. GDB为什么必须使用与运行内核匹配的`vmlinux`？
   - 答：匹配的`vmlinux`才能提供与运行内核一致的符号地址、DWARF源码映射和数据结构布局，否则断点可能设到错误地址，调用栈、变量和源码行也可能解析错误。
4. built-in与module在构建、加载和卸载上有什么区别？
   - 答：built-in构建在内核中，随内核加载不能卸载。module独立构建为ko文件，可以动态加载和卸载。
5. 模块加载器为什么需要执行重定位？
   - 答：`.ko`是可重定位ELF，链接时没有最终运行地址。内核加载器为模块各节分配内存后，需要根据实际节地址修正代码和数据中的地址引用，并解析模块对内核导出符号的引用，才能让指令访问正确的函数和数据。
6. oops与kernel panic有什么区别，`oops=panic`改变了什么？
   - 答：oops记录当前内核异常，默认可能终止当前任务后继续运行；kernel panic表示内核认为系统无法安全继续，会停止整个系统。`oops=panic`要求内核在发生oops后立即进入panic，便于保留第一个故障现场并避免继续运行造成二次破坏。
7. instruction pointer和call trace分别说明什么？
   - 答：instruction pointer说明故障函数及偏移，call trace说明故障调用栈。
8. taint标志有什么作用，它是否直接说明故障根因？
   - 答：taint记录内核经历过闭源模块、out-of-tree模块、强制加载、硬件错误等可能影响可信度的状态；它提供调查背景，不直接证明故障根因。本次`[O]=OOT_MODULE`表示加载了树外模块。
9. 为什么模块运行时地址不能直接用`addr2line -e module.ko`解析？
   - 答：`.ko`是可重定位ELF，各节的运行地址由内核加载时分配并可能在每次加载时变化，因此日志中的运行时绝对地址不能直接对应文件内地址。日志给出`函数名+偏移`时，应先从`.ko`取得函数的ELF符号地址，再加上函数内偏移后交给`addr2line`；本次为`0x10+0x25=0x35`。
10. 如何证明故障定位到了正确源码行，而不是相似函数或旧构建产物？
   - 答：先确认运行内核的`kernelrelease`与模块`vermagic`匹配，并保存`vmlinux`、`bzImage`和`.ko`的哈希及构建时间；再用GDB、`addr2line`和`objdump`独立解析同一偏移，比较函数名、源码行和机器码是否与oops中尖括号标出的故障指令一致。本次三种方法都定位到故障版本`null-deref.c:18`的`*ptr = 1`及`movl $0x1,0x0`。

## 14. 实验结束时应保留的产物

- GDB连接及`start_kernel()`断点记录；
- 可正常加载和卸载的基础模块；
- 可控触发NULL pointer dereference的实验模块；
- 完整oops日志；
- GDB、`addr2line`和`objdump`定位记录；
- 修复前后的代码差异；
- 修复后的回归验证记录；
- 本周验收问题答案；
- 一个能够说明第二周成果的Git commit。
