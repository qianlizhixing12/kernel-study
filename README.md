# Linux内核学习实验室

这是一个为期12个月、每周投入8～10小时的Linux内核与驱动学习项目。项目基于Linux 6.12 LTS、QEMU x86_64和系统软件包提供的静态BusyBox，目标是形成能够重复构建、主动破坏、快速恢复和系统调试的内核实验环境。

最终目标是能够编译和调试内核，独立编写基础platform/字符设备驱动，分析常见内核崩溃，追踪网络收发路径。

## 当前进度

进度只在本表维护。只有学习者亲手执行实验、解释关键概念并完成验收问题后，才能把对应内容标记为完成。

| 周次      | 状态   | 已完成内容                                                                 | 下一步                                                      |
| --------- | ------ | -------------------------------------------------------------------------- | ----------------------------------------------------------- |
| 第1周     | 进行中 | 实验环境、Linux 6.12.96编译配置、initramfs和QEMU脚本已经准备并通过自动测试 | 学习者按照`notes/week01.md`亲手复现，提交命令输出并完成自测 |
| 第2周     | 未开始 | —                                                                          | GDB、内核模块、NULL pointer oops和地址定位                  |
| 第3～48周 | 未开始 | —                                                                          | 按本文“每周学习路线”逐周展开                                |

## 仓库结构

```text
kernel-study/
├── linux/             # Linux内核源码和编译产物，不提交Git
├── rootfs-overlay/    # 放入initramfs的自定义文件
├── modules/           # 内核模块
├── scripts/           # 环境检查、构建和启动脚本
├── labs/              # 实验代码
├── notes/             # 已开始周次的实验过程、问题和结论
├── configs/           # 已验证的构建配置
├── build/             # initramfs等生成物，不提交Git
└── README.md          # 长期计划、公共规则和执行进度
```

## 文档导航

- [第1周：编译内核并用QEMU启动](notes/week01.md)
- 第2～48周学习路线见本文“每周学习路线”

## 执行原则

每个知识点都遵循以下闭环：

```text
学习概念
→ 提出具体问题
→ 阅读少量相关源码
→ 编写或修改代码
→ 主动制造错误
→ 使用工具定位
→ 记录调用路径和结论
```

必须遵守：

1. 不做无目标的源码通读；
2. 不把低版本内核作为主实验基线；
3. 阅读源码前先提出问题并确定入口；
4. 学习API时确认目标内核版本；
5. 每个关键对象都要说明创建者、持有者和释放者；
6. 每条关键路径都要说明运行上下文；
7. 不只验证正常路径，还要验证错误回滚、并发和卸载路径；
8. 每周至少形成一种可验证产物。

避免：

- 从头到尾通读完整内核源码；
- 只看书和视频而不做实验；
- 大量抄写函数和结构体，却不能解释执行上下文与生命周期；
- 写完`hello_module`就认为掌握驱动；
- 照搬旧书、博客或AI生成的内核API；
- 同时学习过多子系统。

## 为什么采用问题驱动的源码阅读

内核规模远超短期认知容量，源码也不是按教学顺序组织的。一个功能经常横跨系统调用、VFS、调度、内存、驱动和架构代码。没有运行现场时，锁、引用计数、错误回滚和中断上下文等条件很难真正理解。

正确方法：

```text
提出具体问题
→ 通过实验找到入口和调用栈
→ 阅读主路径上的关键函数与数据结构
→ 暂时跳过无关分支
→ 修改或插桩验证理解
→ 记录路径、生命周期、上下文和锁
```

例如，不泛泛地阅读网络协议栈，而是回答：

- 用户态调用`sendto()`后，第一个进入的内核函数是什么？
- `sk_buff`在哪里分配，由谁释放？
- 数据包何时进入qdisc和驱动？
- 路径运行在进程上下文还是软中断上下文？

第1～3个月以实验主路径为主；第4～8个月系统阅读小型子系统或真实驱动；第9～12个月再通过提交记录、邮件讨论和跨版本diff理解设计演进。

## 为什么选择Linux 6.12 LTS

低版本内核可以用于维护特定产品、理解历史设计或分析历史漏洞，但不适合作为当前学习主线：

- API和推荐写法持续变化；
- 新LTS具有更完整的KASAN、KCSAN、UBSAN、lockdep、BPF、ftrace等工具；
- 新硬件和主线驱动优先支持较新内核；
- 当前源码、官方文档、修复和社区讨论更容易对应；
- 低版本并不必然更简单，可能包含更多历史做法和厂商补丁。

需要研究或维护旧版内核时：

```text
先在6.12 LTS理解当前机制
→ 确认老内核版本和厂商补丁
→ 使用Git、源码和文档比较API
→ 理解变化原因
→ 编写兼容或迁移方案
```

## 时间安排

| 时间                       | 内容                       |
| -------------------------- | -------------------------- |
| 工作日晚上2次，每次1.5小时 | 原理、源码和官方文档       |
| 工作日晚上1次，1小时       | 整理笔记和调用路径         |
| 周末半天，4～5小时         | 编码、编译、启动和调试实验 |
| 每月最后一个周末           | 阶段复盘和项目整理         |

工作繁忙时保持每周最低4小时，不通过临时熬夜追赶进度。

每周至少形成一种产物：

- 一段可运行代码；
- 一张调用路径图或时序图；
- 一份调试记录；
- 一篇技术笔记；
- 一个符合规范的Git commit。

## 12个月路线

| 阶段               | 周次   | 主题                                          | 主要产物                        |
| ------------------ | ------ | --------------------------------------------- | ------------------------------- |
| 建立实验环境       | 1～2   | 内核编译、initramfs、QEMU、GDB、模块和oops    | 可重复构建的内核实验室          |
| 内核基本机制       | 3～8   | 模块、源码结构、进程、调度、执行上下文和内存  | 调用路径与错误注入实验          |
| 字符设备与并发     | 9～16  | 字符设备、同步、wait queue和延迟执行          | `/dev/kmsg_queue`               |
| 设备模型与platform | 17～21 | device model、sysfs、platform和Device Tree    | QEMU虚拟platform设备            |
| 中断与硬件接口     | 22～28 | 中断、GPIO、I2C、SPI、DMA和Cache              | 虚拟设备与传感器驱动分析        |
| 内核调试专项       | 29～32 | ftrace、perf、KASAN、lockdep、kmemleak和crash | 《Linux内核常见崩溃与调试手册》 |
| 网络内核专项       | 33～40 | 网络路径、netfilter、eBPF和虚拟网卡           | 网络观测实验与虚拟网络设备      |
| ARM64与真实硬件    | 41～45 | ARM64、GIC、Device Tree和开发板               | 真实硬件驱动实验                |
| 综合项目           | 46～48 | 内核、网络和用户态协同                        | Linux网络与设备状态监控平台     |

## 每周学习路线

进入某一周时，以本节对应内容为基础创建独立的`notes/weekNN.md`，记录亲手执行的命令、源码阅读、错误日志、调用路径和结论。尚未开始的周次不提前创建空笔记。

| 周次       | 学习内容                                                                                                            | 实验与产物                                                                                    | 核心验收问题                                                                                               |
| ---------- | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| 第2周      | GDB、QEMU `-s`/`-S`、内核模块、built-in与module、oops和符号定位                                                     | 编写模块；GDB连接QEMU；制造NULL pointer dereference；使用GDB和`addr2line`定位                 | `vmlinux`与`bzImage`为什么用途不同？`-s`与`-S`分别做什么？如何阅读instruction pointer、call trace和taint？ |
| 第3～4周   | 内核源码目录、Kconfig、Makefile、Kbuild、`EXPORT_SYMBOL`、module parameter、dynamic debug、错误回滚                 | 模块参数；跨模块导出函数；制造初始化失败并验证资源全部释放                                    | Kconfig、Kbuild和Makefile分别负责什么？初始化失败由谁回滚？`EXPORT_SYMBOL_GPL`有什么限制？                 |
| 第5～6周   | `task_struct`、系统调用、process/interrupt context、preemption、`current`、进程状态和调度                           | 追踪`getpid()`、`openat()`、`read()`、`write()`；通过procfs输出进程信息                       | 系统调用进入内核后属于哪个进程？哪些上下文允许睡眠？`read()`到具体文件操作经过哪些层？                     |
| 第7～8周   | 虚拟内存、页表、TLB、伙伴系统、slab/slub、`kmalloc`、`vmalloc`、GFP flags、用户态数据复制                           | 比较分配接口；使用kmemleak和KASAN分析泄漏、越界和UAF                                          | 中断上下文为什么不能随便使用`GFP_KERNEL`？为什么不能直接解引用用户指针？`kmalloc`与`vmalloc`如何选择？     |
| 第9～11周  | 字符设备、`dev_t`、`cdev`、`file_operations`、阻塞/非阻塞IO、`poll`、udev                                           | 实现`/dev/kmsg_queue`，支持`kfifo`、阻塞、`O_NONBLOCK`、`poll/epoll`、ioctl、多进程和正确卸载 | `inode`与`struct file`有什么区别？如何避免lost wakeup？卸载时如何等待已有访问结束？                        |
| 第12～14周 | atomic、spinlock、mutex、completion、wait queue、引用计数、RCU、内存屏障、锁顺序                                    | 保护共享状态；阻塞读取；completion；使用lockdep和KASAN分析死锁及并发UAF                       | spinlock与mutex如何选择？为什么持有spinlock不能睡眠？引用计数为什么不能解决所有UAF？                       |
| 第15～16周 | hard IRQ、softirq、timer、workqueue、delayed work、kernel thread、threaded IRQ                                      | timer统计；workqueue和内核线程处理消息；安全停止所有异步任务                                  | 各机制运行在什么上下文？哪些允许睡眠？`cancel_work_sync()`保证什么？                                       |
| 第17～18周 | device、driver、bus、class、sysfs、kobject、driver binding、deferred probe、devres                                  | 验证“设备注册→总线匹配→驱动绑定→probe→sysfs节点”                                              | 总线如何match？`-EPROBE_DEFER`后发生什么？`devm_*`资源何时释放？                                           |
| 第19～21周 | platform device/driver、resource、MMIO、Device Tree、`compatible`、`reg`、`interrupts`、phandle                     | 实现QEMU虚拟platform设备，覆盖DT匹配、MMIO、sysfs、`probe()`/`remove()`和失败回滚             | platform总线适合什么设备？`reg`是什么地址？`devm_ioremap_resource()`多做了什么？                           |
| 第22～24周 | GIC、IRQ number、hard/threaded IRQ、中断共享、触发方式、亲和性和中断风暴                                            | 虚拟设备触发中断；拆分上半部和后续处理；统计延迟；验证卸载并发安全                            | 硬件中断号与Linux IRQ number有何区别？edge与level如何处理？`free_irq()`返回时保证什么？                    |
| 第25～27周 | GPIO descriptor、pinctrl、I2C、regmap、SPI、Device Tree binding和YAML schema                                        | 分析主线I2C传感器驱动，画出匹配、`probe()`、寄存器访问和用户态接口路径                        | adapter/client/driver分别是什么？regmap解决什么问题？binding为什么需要schema？                             |
| 第28周     | MMIO、coherent/streaming DMA、DMA mapping、Cache coherence、scatter-gather、IOMMU、memory barrier                   | 解释DMA API边界，不直接编写复杂PCIe或网卡DMA驱动                                              | coherent与streaming DMA生命周期有何区别？mapping为什么需要方向？Cache一致性与内存序为何不同？              |
| 第29～32周 | printk、dynamic debug、GDB、ftrace、perf、KASAN、UBSAN、lockdep、kmemleak、kdump、crash、eBPF                       | 制造NULL、UAF、越界、泄漏、atomic sleep、double free、deadlock和卸载后访问；形成调试手册      | 各调试工具观察角度有什么区别？KASAN能证明什么？如何阅读锁依赖链？kdump与crash分别在哪个阶段工作？          |
| 第33～35周 | `socket`、`sock`、`sk_buff`、`net_device`、NAPI、softirq、qdisc、routing、netfilter、namespace、veth/bridge/tap/tun | 先追踪UDP，再追踪TCP的完整收发路径                                                            | `socket`与`sock`的使用者是谁？NAPI如何降低中断压力？qdisc在哪里？收包为何常运行于softirq？                 |
| 第36～38周 | netfilter与eBPF                                                                                                     | 至少完成两个：流量统计、目的地址统计、TCP生命周期、重传观测、进程流量、发送延迟分析           | netfilter hook在哪些位置？程序类型如何限制helper？verifier验证什么？如何测量观测开销？                     |
| 第39～40周 | `net_device`生命周期和网络设备操作                                                                                  | 实现虚拟网卡，覆盖注册、`ndo_open`、`ndo_stop`、`ndo_start_xmit`、统计、并发、压力和反复卸载  | TX queue何时停止和唤醒？统计如何并发安全？注销时如何阻止释放后访问？                                       |
| 第41～42周 | ARM64寄存器、Exception Level、MMU、页表、exception vector、GIC、Device Tree、Cache和内存屏障                        | 阅读启动和异常处理中的简单汇编                                                                | EL0/EL1/EL2各是什么？exception vector如何分类异常？TTBR、页表和TLB如何配合？弱内存序有何影响？             |
| 第43～45周 | ARM64真实开发板、交叉编译、串口、Device Tree、GPIO、I2C/SPI、suspend/resume                                         | 启动自编内核；修改DT；完成GPIO中断和传感器实验；验证故障恢复及休眠唤醒                        | 工具链、架构和ABI如何对应？如何区分DT、驱动和硬件错误？如何审查主线与BSP差异？                             |
| 第46～48周 | 内核、网络和用户态综合                                                                                              | 完成Linux网络与设备状态监控平台，交付架构图、构建方法、测试、错误注入、性能数据和已知问题     | 三部分接口边界是什么？如何证明生命周期和并发安全？测试如何覆盖正常、错误、压力和恢复？哪些能力已有证据？   |

### 阶段项目要求

`/dev/kmsg_queue`必须提供用户态C测试程序，覆盖单进程、多进程、阻塞、非阻塞和`epoll`；反复加载卸载100次，压力运行至少30分钟，并保证KASAN与lockdep无告警。

系统化调试阶段的每个错误必须形成以下报告：

```text
现象
复现步骤
关键日志
调用栈
根因
修复方法
验证方式
为什么原测试没有发现
```

综合项目包含：

- 内核部分：platform driver、Device Tree、GPIO/I2C/SPI中至少一种、中断、workqueue、sysfs或字符设备接口、并发和资源生命周期；
- 网络部分：eBPF或netfilter、TCP重传/连接/流量指标、perf/ftrace性能分析；
- 用户态部分：C/C++ 守护进程、epoll、配置、日志、故障恢复、systemd、单元测试、交叉编译和CI；
- 质量验证：KASAN、lockdep、kmemleak、压力测试、错误注入和性能测试。

综合项目必须提供完整的源码、构建方法、测试记录、错误注入结果、性能数据和已知问题。

## 每周执行流程

周初在对应notes文件填写：

```text
本周主题：
目标内核版本：
准备理解的问题：
准备阅读的源码：
准备完成的实验：
验收条件：
```

周末在同一文件补充：

```text
实际完成：
遇到的错误：
错误根因：
关键调用路径：
仍未理解的问题：
下周是否需要补课：
```

检查项：

- [ ] 阅读源码前已经提出具体问题；
- [ ] 阅读范围服务于本周实验或调用路径；
- [ ] API已在目标版本源码或官方文档中核对；
- [ ] 参考低版本资料时记录了版本差异；
- [ ] 源码阅读形成了调用路径、实验结论或代码修改；
- [ ] 能说明关键对象的生命周期；
- [ ] 能说明关键代码的执行上下文。

## 资料优先级

1. 目标版本的内核源码；
2. [Linux Kernel官方文档](https://docs.kernel.org/)；
3. [Linux Kernel Labs](https://linux-kernel-labs.github.io/)；
4. 内核邮件列表、Git提交记录和maintainer文档；
5. 高质量书籍；
6. 博客和视频。

书籍用于建立知识框架。旧资料中的API必须对照目标内核源码和官方文档，不直接照搬。

## AI使用边界

AI可以辅助：

- 解释结构体和代码路径；
- 提供源码入口线索；
- 生成用户态测试程序；
- 设计错误注入场景；
- 初步解读编译错误和oops；
- 整理调试报告；
- 比较实现方案。

AI不能代替学习者完成整套实验。学习者应亲手执行命令、阅读输出、修改代码和回答验收问题。

以下内容不能直接相信AI：

- 内核API与目标版本兼容性；
- 锁、并发和对象生命周期；
- 原子上下文与睡眠；
- DMA、Cache和内存屏障；
- Device Tree binding；
- 硬件寄存器定义。

固定验证流程：

```text
对照源码 → 编译 → 静态检查 → KASAN/lockdep → 压力测试 → 人工检查异常路径和生命周期
```
