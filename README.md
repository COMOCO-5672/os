# os —— 手撸操作系统

x86-64 裸机操作系统，学习项目。技术栈：C / GNU as / QEMU / GRUB(Multiboot2)。

配套 18 周计划见上级目录 `os-dev-plan.md`。

---

## 1. 环境安装（macOS / Apple Silicon）

```bash
# 基础工具
brew install qemu nasm xorriso mtools

# 交叉工具链（宿主自带 gcc/ld 不能用来编内核，见下文）
brew install x86_64-elf-binutils x86_64-elf-gcc x86_64-elf-gdb

# GRUB：需要两份
brew install i686-elf-grub        # BIOS 平台(i386-pc) —— 项目默认走这个
brew install x86_64-elf-grub      # UEFI 平台(x86_64-efi) —— 备用
```

**为什么有两个 grub**：`x86_64-elf-grub` 只编译了 EFI 平台，用它做的 ISO
在 SeaBIOS 下无法引导（El Torito 记录里只有 UEFI 镜像），而且 EFI 下没有
`0xB8000` 传统 VGA 文本模式。`i686-elf-grub` 带 i386-pc 平台，做的 ISO 是
BIOS 引导，`0xB8000` 文本模式可用——这正是 W3 需要的。

### 为什么不能用宿主工具链

macOS 自带的 `gcc` 其实是 clang、`ld` 只能产出 Mach-O 格式。用它编内核会出现
一堆诡异错误。必须使用 `x86_64-elf-*` 交叉工具链。

### 国内网络：换 Homebrew 镜像

`ghcr.io` 在国内经常被限速到几十 KB/s（160MB 的 GCC bottle 要一个多小时）。
改用清华 TUNA 镜像，实测秒级完成：

```bash
export HOMEBREW_API_DOMAIN=https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api
export HOMEBREW_BOTTLE_DOMAIN=https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles
```

**坑**：如果之前用默认源跑过 `brew`，本地 API 缓存里会留着旧版本号
（例如 GCC 16.1.0，而镜像上只有 16.2.0），导致镜像 404 后静默回退到 ghcr 慢速下载。
解决：先删掉缓存再装。

```bash
rm -rf ~/Library/Caches/Homebrew/api
```

自检：

```bash
make check
```

---

## 2. 常用命令

| 命令 | 作用 |
|---|---|
| `make` | 编译内核并打包 `build/os.iso` |
| `make run` | QEMU 启动（开窗口 + 串口输出到当前终端） |
| `make run-headless` | 无窗口，只看串口日志，适合快速回归 |
| `make debug` | QEMU 暂停在起点等待 GDB 连接（端口 1234） |
| `make check` | 检查工具链是否齐全 |
| `make clean` | 清理产物 |

`make` 变量：

- `BITS=32|64` —— W1–W3 用 32，W4 进长模式后改 64（会自动切到 C 编译规则）
- `GRUB_PLATFORM=bios|uefi` —— 默认 `bios`

GDB 连接：

```bash
x86_64-elf-gdb build/kernel.elf -ex "target remote :1234"
```

---

## 3. 当前进度

| 阶段 | 状态 | 说明 |
|---|---|---|
| W1 工具链 / Makefile / ISO | ✅ 已验证 | 一条 `make run` 走通：GRUB → 内核 → 串口 + VGA |
| W2 ELF / 链接脚本 / GDB | ⏳ 你的任务 | 用 `readelf`/`objdump` 读懂产物，跑通 `make debug` |
| W3 Multiboot2 + VGA terminal | ⏳ 你的任务 | 把 `vga_puts` 重构成带滚屏的 `terminal_*` |
| W4 长模式 + C 运行时 | ⏳ 你的任务 | `BITS=64`，GDT/页表/`CR0.PG`，跳进 `kmain()` |

### W1 验收证据

```console
$ make run-headless
  Booting `os (multiboot2)'
[os] GRUB handoff OK, we are alive in 32-bit protected mode
[os] multiboot2 magic verified (0x36D76289)
```

VGA 显存（可用 QEMU 监视器 `xp/48xb 0xb8000` 自查）：

```
00000000000b8000: 0x48 0x0f 0x65 0x0f 0x6c 0x0f 0x6c 0x0f   H.e.l.l
```

---

## 4. 骨架里已经给了什么

- `Makefile`：`BITS` 开关（32/64）、`GRUB_PLATFORM` 开关（bios/uefi）、
  交叉工具链、ISO 打包、QEMU 运行、`make check`
- `linker.ld`：`.multiboot_header` 前置、1MB 加载地址、`__bss_start/__bss_end`
- `arch/x86_64/boot.S`：Multiboot2 头、`_start`、自建栈、清零 `.bss`、
  串口 + VGA 最小输出（**故意不做抽象**，W3 交给你重构）
- `iso/boot/grub/grub.cfg`：GRUB 输出同时接 VGA 与串口（无窗口调试必备）

## 5. 骨架里已经踩过的坑（别再踩一遍）

1. **`rep stosb` 会冲掉 `%eax`**：清零 `.bss` 用的 `xorl %eax,%eax` 会把
   bootloader 放在 `%eax` 里的 multiboot2 magic 抹掉。必须先搬到 `%esi`。
2. **不要请求 framebuffer tag**：Multiboot2 头里请求 framebuffer(8) 会让 GRUB
   去切换显卡模式，BIOS 下 `0xB8000` 文本模式就没了，还会报
   `no suitable video mode found`。
3. **GRUB 默认只往 VGA 打印**：`-display none` 时 GRUB 的报错全看不见。
   在 `grub.cfg` 里加 `terminal_output serial console` 才能串口调试。
4. **`grub-mkrescue` 需要 `mtools`**（`mformat`），否则报
   `mformat invocation failed`。
5. **RWX 段警告**：目前所有段在一个 LOAD 里，链接器会警告
   `has a LOAD segment with RWX permissions`。等 W4/W9 有分页时用 `PHDRS`
   拆成 RX / RW 两个段消除。

## 6. 注意：`x86_64-elf-gdb` 会带入 `python@3.14`

`x86_64-elf-gdb` 依赖 `python@3.14`。Homebrew 在 link 一个新版 python 时，会把
**无版本号**的别名（`python3` `pip3` `idle3` `pydoc3` `wheel3` `python3-config`）
从旧版本抢到新版本 —— 于是系统里原有的 `python3` 会从 3.13 变成 3.14，
而 3.14 看不到 3.13 用户 site-packages（`~/Library/Python/3.13/...`）里已装的包。

自查：

```bash
ls -l /opt/homebrew/bin/ | grep -E ' (python3|pip3) '
python3 -V
```

修复（保留 3.14 可用，只把无版本号别名还回去）：

```bash
for n in idle3 pip3 pydoc3 python3 python3-config wheel3; do
  ln -sfn "../Cellar/python@3.13/3.13.5/bin/$n" "/opt/homebrew/bin/$n"
done
```

⚠️ 以后再执行 `brew link python@3.14` 或升级 python，别名会**再次被抢走**。

---

## 7. 已知边界

- 当前是 **32 位保护模式**，C 代码尚未启用（GRUB 交付态即 32 位）
- `vga_puts` 无滚屏、无光标、无 `\n` 处理 —— 这是 W3 的练习内容
- 串口 115200 8N1，日志走 `-serial stdio`
