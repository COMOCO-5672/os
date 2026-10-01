# os —— 手撸操作系统

x86-64 裸机操作系统，学习项目。技术栈：C / GNU as / QEMU / GRUB(Multiboot2)。

配套 18 周计划见上级目录 `os-dev-plan.md`。

---

## 环境

macOS (Apple Silicon) + Homebrew：

```bash
brew install qemu nasm xorriso \
             x86_64-elf-binutils x86_64-elf-gcc x86_64-elf-grub x86_64-elf-gdb
```

**关键点**：macOS 自带的 `gcc` 是 clang、`ld` 只能产出 Mach-O，**不能**用来编内核。
必须使用 `x86_64-elf-*` 交叉工具链。

自检：

```bash
make check
```

## 常用命令

| 命令 | 作用 |
|---|---|
| `make` | 编译内核并打包 `build/os.iso` |
| `make run` | QEMU 启动（开窗口 + 串口输出到当前终端） |
| `make run-headless` | 无窗口，只看串口日志，适合快速回归 |
| `make debug` | QEMU 暂停在起点等待 GDB 连接（端口 1234） |
| `make clean` | 清理产物 |

GDB 连接方式：

```bash
x86_64-elf-gdb build/kernel.elf -ex "target remote :1234"
```

## 当前进度

| 阶段 | 状态 | 说明 |
|---|---|---|
| W1 工具链 / Makefile / ISO | ✅ | 一条 `make run` 走通全链路 |
| W2 ELF / 链接脚本 / GDB | ⏳ 你的任务 | 用 `readelf`/`objdump` 读懂产物，跑通 `make debug` |
| W3 Multiboot2 + VGA terminal | ⏳ 你的任务 | 把 `vga_puts` 重构成带滚屏的 `terminal_*` |
| W4 长模式 + C 运行时 | ⏳ 你的任务 | `BITS=64`，GDT/页表/`CR0.PG`，跳进 `kmain()` |

## 骨架里已经给了什么

- `Makefile`：`BITS` 开关（32/64）、交叉工具链、ISO 打包、QEMU 运行、`make check`
- `linker.ld`：`.multiboot_header` 前置、1MB 加载地址、`__bss_start/__bss_end`
- `arch/x86_64/boot.S`：Multiboot2 头、`_start`、自建栈、清零 `.bss`、
  串口 + VGA 最小输出（**故意不做抽象**，W3 交给你重构）

## 已知边界

- 当前是 **32 位保护模式**，C 代码尚未启用（GRUB 交付态即 32 位）
- `vga_puts` 无滚屏、无光标、无 `\n` 处理 —— 这是 W3 的练习内容
- 串口配置波特率 115200 8N1，日志走 `-serial stdio`
