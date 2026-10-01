# 手撸操作系统 · 18 周执行计划

> 技术栈：**C17 + x86-64 + QEMU + GRUB(multiboot2)**
> 节奏：**每周 8–10 小时**（建议 2 次 × 4h 深度会话 + 1h 复盘）
> 起点：理论扎实、无裸机经验
> 目标：第 18 周结束时，能在 QEMU 里跑起一个用户态 shell，并自己写出 MBR 引导程序

---

## 0. 三条铁律

1. **没在屏幕/串口上验证过的功能，不算完成。** 每周的"验收标准"必须亲眼跑通。
2. **一次只引入一个新变量。** 新功能没跑通前，不叠加第二个新功能。
3. **每次会话结束，仓库必须处于"可编译 + 可启动"状态，并打 git tag。**
   回退能力是你唯一的安全网，宁可回退也不要带着坏状态往下走。

---

## 1. 环境基线（macOS 宿主）

macOS 自带的 `gcc` 其实是 clang，`ld` 只能产出 Mach-O。**必须用交叉工具链**，否则后面会出现各种诡异的链接错误。

```bash
brew install qemu nasm xorriso mtools
brew install x86_64-elf-gcc x86_64-elf-binutils x86_64-elf-gdb
```

如果你更倾向 LLVM：

```bash
clang --target=x86_64-unknown-none -ffreestanding -nostdlib -mno-red-zone -fno-stack-protector
```

**编译内核的固定参数**（少一个都会出事）：

| 参数 | 作用 |
|---|---|
| `-ffreestanding` | 不假设有标准库 |
| `-nostdlib` / `-nostdinc` | 不链接/不搜索宿主库 |
| `-fno-stack-protector` | 没有 `__stack_chk_fail` 可用 |
| `-mno-red-zone` | 中断会踩坏 red zone |
| `-fno-omit-frame-pointer` | 为了能栈回溯 |
| `-mcmodel=kernel` | 内核在高半区 |
| `-mgeneral-regs-only` | 内核别用 SSE 寄存器（简化上下文切换） |
| `-Wall -Wextra -Werror` | 裸机错误代价极高，让编译器兜住 |

---

## 2. 阶段地图

| 阶段 | 周次 | 主题 | 阶段产物 |
|---|---|---|---|
| 一 | W1–W2 | 工具链与调试基建 | 一条命令产出 ISO，GDB 能单步内核 |
| 二 | W3–W4 | 引导与 64 位运行时 | 64 位 C 的 `kmain()` 跑起来 |
| 三 | W5–W7 | 可观测性 + 中断异常 | 串口日志、panic、定时器、键盘 |
| 四 | W8–W10 | 内存管理 | 物理页分配器 + 虚拟内存 + 内核堆 |
| 五 | W11–W14 | 并发与进程 | 抢占式调度 + 系统调用 + fork/exec |
| 六 | W15–W18 | 存储与用户态 | 块设备 + 文件系统 + 用户态 shell |

---

## 3. 逐周计划

### Week 1 — 工具链与构建系统

**目标**：一条 `make` 命令产出可被 QEMU 启动的 ISO。

- [ ] 安装交叉工具链，验证 `x86_64-elf-gcc -v` 与 `x86_64-elf-ld -v`
- [ ] 搭目录结构：`src/`、`include/`、`arch/x86_64/`、`kernel/`、`drivers/`、`linker.ld`
- [ ] 写 Makefile：编译 `.c/.S` → `x86_64-elf-ld -T linker.ld` → 生成 `kernel.elf`
- [ ] 写 `iso/grub/grub.cfg` + `grub-mkrescue` 打包
- [ ] QEMU 启动脚本：`qemu-system-x86_64 -cdrom os.iso -serial stdio -no-reboot -no-shutdown`
- [ ] 初始化 git，提交第一个 commit

**验收**：`make run` 能启动 QEMU 且 GRUB 菜单出现。
**坑**：用宿主 `ld` 直接链接会失败或产出错误格式；忘记 `-ffreestanding` 会引入 libc 符号。

---

### Week 2 — ELF、链接脚本与 GDB 调试链

**目标**：彻底搞清"我的代码被放在哪里、怎么被加载、怎么被观察"。

- [ ] `linker.ld`：定义 `. = 0x100000`（或高半区 `0xFFFFFFFF80000000`），划分 `.text/.rodata/.data/.bss`，用 `KEEP()` 保护 multiboot 段
- [ ] 用 `readelf -h -S -l`、`objdump -d`、`nm` 反复观察产物，能说清每个 section 的 VMA
- [ ] 复习 System V AMD64 调用约定：参数寄存器顺序、返回值、callee-saved（`rbx rbp r12-r15`）、栈 16 字节对齐
- [ ] 打通 GDB：`qemu -s -S` + `x86_64-elf-gdb kernel.elf -ex "target remote :1234"`
- [ ] 练习：断点、`info registers`、`x/16xb addr`、`layout src`、`monitor info mem`

**验收**：能在 GDB 里单步一条汇编指令，并读出 `rsp`/`rip` 指向的内存内容。
**坑**：VMA/LMA 区别不懂会在高半区内核上卡死；`.bss` 必须显式清零。

---

### Week 3 — GRUB + multiboot2 Hello World

**目标**：第一次看到自己写的代码在裸机上输出。

- [ ] 写 multiboot2 header（magic `0xE85250D6`，含结束标签）
- [ ] `_start` 入口，先把 `rax=magic`、`rbx=info` 存起来备用
- [ ] VGA 文本模式输出：`0xB8000`，80×25，每字符 2 字节（ASCII + 属性）
- [ ] 封装 `terminal_putchar` / `terminal_write`，实现滚屏

**验收**：屏幕上出现彩色 "Hello OS"，并且能打印滚屏测试。
**坑**：header 必须位于文件前 8KB 内并 8 字节对齐；GRUB 已替你开好 A20 并设了 flat GDT，别重复做。

---

### Week 4 — 进入 64 位长模式

**目标**：从 GRUB 交出的 32 位环境，进入 64 位 C 世界。

- [ ] 建立 64 位 GDT：null / kernel-code(`0x08`) / kernel-data(`0x10`)
- [ ] 页表：PML4 → PDPT → PD，先用 2MB 大页 identity map 低 1GB
- [ ] 开长模式：`CR4.PAE=1` → `EFER.LME=1` → `CR0.PG=1|PE=1`
- [ ] `lgdt` → `lretq` 远跳转到 64 位代码段 → 重载数据段
- [ ] 在 `.bss` 里分配 16KB 对齐的内核栈，`mov rsp, stack_top`
- [ ] 跳进 C 的 `kmain(uint32_t magic, uint32_t info_addr)`

**验收**：`kmain` 里的 `terminal_write()` 正常输出，且 GDB 里 `rip` 位于高地址。
**坑**：忘了 identity map 前 1GB → 一开分页就三重故障；栈没 16 字节对齐 → SSE/ABI 相关诡异崩溃。

---

### Week 5 — 可观测性（本周投入回报率最高）

**目标**：让内核会"说话"，后面所有阶段的调试速度由这一周决定。

- [ ] 串口 COM1 初始化（`0x3F8`，115200 8N1），`-serial stdio` 直接看到输出
- [ ] 实现 `kprintf`：变参、`%d %u %x %p %s %c`、宽度与补零
- [ ] `KASSERT` / `panic` 宏，打印 `__FILE__:__LINE__` 与表达式原文
- [ ] 栈回溯：沿 `rbp` 链遍历，打印返回地址（后续用 `addr2line` 还原函数名）
- [ ] 日志分级：`DEBUG/INFO/WARN/PANIC`

**验收**：`KASSERT(1 == 2)` 触发时，串口打出文件、行号、寄存器快照与调用栈。
**坑**：`%d` 对负数、`%p` 对齐不处理，后面调试会读到假信息。

---

### Week 6 — IDT 与 CPU 异常

**目标**：让所有异常都变成"有信息可查"的事件，而不是静默重启。

- [ ] 构造 IDT（256 项），门描述符字段：offset / selector / type(`0x8E`) / IST
- [ ] 写 ISR 桩：无错误码的异常补 `0`，统一压栈结构，保存 caller-saved 寄存器
- [ ] 覆盖关键异常：`#DE(0) #BP(3) #UD(6) #DF(8) #GP(13) #PF(14)`
- [ ] 解析 `#PF` 错误码位（P/W/U/RSVD/ID）并读取 `CR2`
- [ ] 建立"三重故障调试法"：`qemu -d int,cpu_reset -no-reboot`，看最后一条异常链

**验收**：制造除零 → 打印 `#DE` 与寄存器；访问未映射地址 → 打印 `#PF` 与出错线性地址。
**坑**：把 `#DF` 当成普通异常调试会浪费一整晚；IST 没配好时 `#DF` 无法可靠捕获。

---

### Week 7 — 定时器与键盘

**目标**：内核第一次"与时间、与人"交互。

- [ ] 8259 PIC 重映射到 `0x20–0x2F`，正确 EOI，屏蔽无关中断
- [ ] PIT 通道 0 mode 3，配置到 100Hz
- [ ] PS/2 键盘：读 `0x60`，scancode set 1 → ASCII 映射表
- [ ] 统一 IRQ 分发层，注册 handler

**验收**：串口每秒打印 100 次 tick；按键能在屏幕上显示对应字符。
**坑**：忘记 EOI 会导致只响应一次中断；PIT 除数算错导致频率离谱。

---

### Week 8 — 物理内存管理

**目标**：能可靠地分配和归还物理页。

- [ ] 从 multiboot2 information 里解析 memory map（或 E820）
- [ ] 位图分配器：4KB 页粒度，预先标记内核 ELF、VGA、低端保留区
- [ ] 接口：`pmm_alloc_page()` / `pmm_free_page()` / `pmm_alloc_pages(n)`
- [ ] 内核内自测：随机分配 1000 页，断言互不重叠；全部释放后能重新分配

**验收**：启动时打印物理内存总量/可用量；自测全部通过。
**坑**：把内核自身占用的物理页分配出去 → 随机崩溃，极难定位。第一件事就是保护自己。

---

### Week 9 — 虚拟内存

**目标**：掌握四级页表，能自己造映射。

- [ ] 实现页表遍历与按需创建：`PML4 → PDPT → PD → PT`
- [ ] `vmm_map(virt, phys, flags)` / `vmm_unmap(virt)` / `vmm_translate(virt)`
- [ ] 建立 HHDM：把整段物理内存映射到 `0xFFFF800000000000`，方便直接访问物理地址
- [ ] 引入 `INVLPG` 与 TLB 一致性意识
- [ ] 内核空间布局定稿（写进文档）：HHDM 区 / 内核镜像区 / 堆区 / 栈区

**验收**：把任意物理页映射到任意虚拟地址并成功读写；`unmap` 后访问立即触发 `#PF`。
**坑**：修改页表后不 `INVLPG`；忘记设置 `PRESENT`/`RW` 位；用了非对齐物理地址。

---

### Week 10 — 内核堆

**目标**：内核里能有 `kmalloc/kfree`。

- [ ] 设计堆区虚拟地址范围，按需映射物理页
- [ ] 实现 slab 或 size-class freelist 分配器
- [ ] 保证对齐（至少 16 字节）、合并空闲块、检测 double free
- [ ] 混沌自测：随机 alloc/free 序列跑 10 万次，断言堆结构完好

**验收**：`kmalloc` 返回的内存可写可读；长跑自测不崩、不漏（统计分配/释放计数相等）。
**坑**：没有对齐保证会在后面结构体访问时踩到性能与正确性问题。

---

### Week 11 — 线程与调度

**目标**：内核里能同时存在多个执行流。

- [ ] 定义 TCB：`rsp`、状态、内核栈、pid、时间片
- [ ] 汇编实现 `context_switch(prev, next)`，保存/恢复 callee-saved + `rsp`
- [ ] 线程创建：初始化栈使首次调度跳到 trampoline
- [ ] 就绪队列 + Round Robin 调度器

**验收**：3 个线程各自循环打印自增计数，能观察到交替执行；线程 A 能创建线程 B。
**坑**：栈未按 ABI 布置导致 trampoline 一进去就崩；切换时忘记保存 `rbx` 等寄存器。

---

### Week 12 — 抢占与同步原语

**目标**：调度由时间驱动，并发访问有保护。

- [ ] 在定时器中断返回路径上触发 `schedule()`，实现抢占
- [ ] 自旋锁：基于 `xchg`/`cmpxchg`；提供 `irq_save/irq_restore` 变体
- [ ] 信号量、mutex、等待队列、`sleep(ms)` / `wakeup()`
- [ ] 处理"关中断 + 持锁"顺序问题，避免死锁

**验收**：N 个线程对共享计数器各加 10000 次，加锁后结果精确正确；`sleep(100)` 唤醒时机误差可接受。
**坑**：中断上下文里睡眠 → 死锁；锁里调用可能睡眠的函数 → 死锁。

---

### Week 13 — 系统调用与用户态

**目标**：第一次从 ring 3 进入内核。

- [ ] 配置 `EFER.SCE`、`STAR`/`LSTAR`/`FMASK` MSR，使用 `syscall`/`sysret`
- [ ] GDT 增加用户代码/数据段（DPL=3）；TSS 设置 `rsp0` 指向内核栈
- [ ] 系统调用分发表：`sys_write`、`sys_exit`、`sys_getpid`
- [ ] 页表项设置 `U/S` 位；内核页面对用户不可见
- [ ] GRUB module 加载初始 ramdisk（cpio/tar），从中读取用户 ELF 并加载

**验收**：ring 3 程序调用 `sys_write` 在串口输出字符串，随后 `sys_exit` 正常终止。
**坑**：`sysret` 的返回地址/栈切换时机搞错；用户段选择子 RPL 不对；内核栈没切换导致用户栈被污染。

---

### Week 14 — 进程模型

**目标**：进程能创建、替换、等待、回收。

- [ ] PCB：地址空间（PML4 物理地址）、fd 表、状态、父子关系
- [ ] 地址空间切换（写 `CR3`）
- [ ] `fork()`：先做深拷贝，再升级为 **COW**（页表只读 + `#PF` 时复制）
- [ ] `exec()`：解析 ELF，替换地址空间
- [ ] `wait()` / `exit()`，僵尸进程回收与孤儿收养

**验收**：用户程序 `fork` 出子进程，父子各自打印不同 pid；`wait` 后子进程被正确回收。
**坑**：COW 忘记处理写时引用计数 → 内存泄漏或提前释放；`exec` 失败未回滚。

---

### Week 15 — 块设备

**目标**：能读写真实磁盘扇区。

- [ ] PCI 枚举：`0xCF8/0xCFC` 配置空间，识别存储控制器
- [ ] ATA PIO（先求能用）或 AHCI（求性能）驱动
- [ ] 扇区读写接口 + 块缓存（LRU）
- [ ] 中断驱动 vs 轮询模式的取舍

**验收**：能读出磁盘第 0 扇区并校验签名（如 `0xAA55`），或读出自己写入的数据。
**坑**：PIO 的 `0x1F7` 状态轮询条件写错 → 读到垃圾；LBA 与 CHS 换算错误。

---

### Week 16 — 文件系统

**目标**：有目录、有文件、能持久化。

- [ ] VFS 抽象：`inode` / `dentry` / `file` 三层，`fd` 表
- [ ] 实现一个简单 FS（类 FAT，或自研带 inode 的结构）
- [ ] 支持 `open/read/write/close/mkdir/readdir`
- [ ] 与块缓存对接，处理元数据一致性

**验收**：能从磁盘读文件内容并打印；创建文件后重启 QEMU 仍然存在。
**坑**：元数据写完就断电导致不一致（这正是日志文件系统的动机，可以在这里理解它）。

---

### Week 17 — 用户态生态

**目标**：让用户态"像个系统"。

- [ ] 最小 libc：syscall 封装、`printf`、`malloc`（基于 `brk`/`mmap`）、`string.h`
- [ ] 写一个用户态 shell：解析命令行、内建 `cd`/`exit`、执行外部程序
- [ ] 提供 `argc/argv` 传递与环境变量基础

**验收**：用户态 shell 能执行内建命令和至少一个外部程序。
**坑**：`malloc` 的 `brk` 语义与内核实现不一致；argv 字符串在用户栈上的布局错误。

---

### Week 18 — 收尾：回头自写引导程序

**目标**：补上当初跳过的引导链，这一周是对 Phase 1 的真正验收。

- [ ] 写 MBR 引导扇区（512 字节，末尾 `0xAA55`）：16 位实模式 → `int 0x13` 读盘 → 跳转
- [ ] 进入保护模式 → 加载内核 → 跳转（可复用 Week 4 的长模式代码）
- [ ] 整理项目 README、架构文档、内存布局图
- [ ] 整理调试案例库（把 18 周踩过的坑全部归档）
- [ ] 规划选修分支（附录 D）

**验收**：不依赖 GRUB，自己的引导程序能把内核加载起来并运行。
**坑**：512 字节限制内写完逻辑需要技巧；读盘重试与 `int 0x13` 扩展调用参数容易错。

---

## 附录 A · 调试速查

**QEMU 常用参数**

```bash
qemu-system-x86_64 -cdrom os.iso \
  -serial stdio \            # 串口日志直接输出
  -s -S \                    # 开 GDB server 并暂停等待
  -no-reboot -no-shutdown \  # 三重故障时停在现场而不是无限重启
  -d int,cpu_reset \         # 打印中断/异常与 CPU 复位原因
  -m 512M
```

**GDB 常用命令**

```
target remote :1234
info registers
x/16xb $rsp
x/8i $rip
break kmain
layout src / layout asm
monitor info mem
monitor info registers
```

**三重故障（Triple Fault）排查顺序**

1. 用 `-d int -no-reboot` 看最后触发的异常序列
2. 若是 `#PF`，读 `CR2`（出错线性地址）与错误码
3. 检查：页表是否映射了当前 `rip` 所在区域？栈是否有效？GDT 是否已加载？
4. 检查：是否在开分页的瞬间没有 identity map

**`#PF` 错误码解读**

| 位 | 含义 |
|---|---|
| 0 (P) | 0=页不存在，1=保护违规 |
| 1 (W) | 0=读，1=写 |
| 2 (U) | 0=内核态，1=用户态 |
| 3 (RSVD) | 保留了非零位（页表项损坏） |
| 4 (ID) | 取指阶段出错 |

---

## 附录 B · 目录结构建议

```
os/
├── Makefile
├── linker.ld
├── iso/grub/grub.cfg
├── include/
│   ├── kernel/
│   └── arch/
├── arch/x86_64/
│   ├── boot.S          # multiboot2 header + _start
│   ├── gdt.c / gdt_flush.S
│   ├── idt.c / isr.S
│   ├── paging.c
│   ├── context.S       # 上下文切换
│   └── syscall_entry.S
├── kernel/
│   ├── kmain.c
│   ├── kprintf.c
│   ├── pmm.c / vmm.c / heap.c
│   ├── thread.c / sched.c / sync.c
│   ├── process.c
│   └── vfs.c / fs/
├── drivers/
│   ├── serial.c / vga.c / keyboard.c / pit.c / pic.c
│   └── pci.c / ata.c
└── user/
    ├── libc/
    └── shell/
```

---

## 附录 C · 里程碑与版本管理

- 每个 Week 的验收通过后：`git tag w03-hello-vga`
- 分支策略：主干保持在"可启动"状态，实验性功能开 `feat/xxx` 分支
- 每周末写一条 5 行以内的 `NOTES.md`：本周完成 / 卡点 / 下周计划
- 更新日志里记录"这周踩的坑 + 定位方法"，这是你 18 周后最值钱的资产

---

## 附录 D · 选修分支（第 18 周后）

| 分支 | 内容 | 难度 |
|---|---|---|
| SMP 多核 | ACPI/MADT 解析、AP 引导、per-CPU 变量、自旋锁升级 | 高 |
| 网络栈 | e1000 驱动、ARP/IP/UDP/TCP、socket API | 高 |
| GUI | 帧缓冲、双缓冲、字体渲染、简单窗口管理 | 中 |
| 现代特性 | 按需分页、内存映射文件、信号、管道、pty | 中 |
| 性能 | 调度器换成 MLFQ/CFS 思路、TLB shootdown、大页 | 中 |

---

## 附录 E · 资料对照

| 阶段 | 主资料 | 对照源码 |
|---|---|---|
| W1–W4 | OSDev Wiki "Bare Bones"、"Setting Up Long Mode" | xv6 `entry.S`/`bootasm.S` |
| W5–W7 | JamesM "Kernel" 系列、OSDev "Interrupts" | xv6 `trap.c`/`trapasm.S` |
| W8–W10 | OSTEP 内存章节、OSDev "Paging" | xv6 `kalloc.c`/`vm.c` |
| W11–W12 | OSTEP 并发章节、xv6 book 第 6–7 章 | xv6 `proc.c`/`spinlock.c` |
| W13–W14 | xv6 book 第 4 章、"syscall" 相关 | xv6 `syscall.c`/`exec.c` |
| W15–W16 | OSDev "ATA"/"PCI"、xv6 book 第 8 章 | xv6 `bio.c`/`log.c`/`fs.c` |
| W17–W18 | OSDev "Bootloader"、Philipp Oppermann 博客 | — |
