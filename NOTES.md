# NOTES —— 每周日志

格式：每周 5 行以内。**"踩的坑 + 定位方法"是这里最值钱的部分**，别省。

---

## W1 工具链与构建系统

- **完成**：交叉工具链装好（binutils/gcc/gdb/grub），`make` 一条命令产出 BIOS 可引导 ISO；
  QEMU 启动后串口与 VGA 双双验证通过。
- **卡点 1**：`ghcr.io` 下载被限速到 25 KB/s，160MB 的 GCC bottle 要 100 分钟。
  改用清华镜像后秒级完成。
- **卡点 2**：换镜像后 GCC 仍走 ghcr —— 本地 Homebrew API 缓存留着旧的 16.1.0，
  而镜像只有 16.2.0，镜像 404 后静默回退。`rm -rf ~/Library/Caches/Homebrew/api` 解决。
- **卡点 3**：ISO 做好了但 SeaBIOS 引导不了。用
  `xorriso -indev build/os.iso -report_el_torito plain` 查出 El Torito 里
  只有 UEFI 镜像 —— `x86_64-elf-grub` 不带 i386-pc 平台。装 `i686-elf-grub` 解决。
- **踩坑 4（真 bug）**：清 `.bss` 的 `xorl %eax,%eax` 冲掉了 `%eax` 里的
  multiboot2 magic，导致 `BAD multiboot2 magic`。改用 `%esi` 中转。
- **定位方法**：GRUB 默认只往 VGA 打印，`-display none` 下全看不见。
  在 `grub.cfg` 加 `terminal_output serial console` 把 GRUB 也接到串口；
  再用 QEMU 监视器 `xp/48xb 0xb8000` 直接 dump 显存验证 VGA。
- **下周计划**：W2 —— 用 `readelf`/`objdump` 读懂 ELF 产物，跑通 `make debug` 单步。

---

<!-- 模板

## Wxx 主题

- 完成：
- 卡点：
- 定位方法：
- 下周计划：

-->
