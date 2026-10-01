# ============================================================
#  os/Makefile —— 手撸操作系统 (x86-64)
#
#  工具链 : x86_64-elf-*  (Homebrew)
#  当前    : W1-W3 阶段, 32 位保护模式 + Multiboot2 + GRUB
#  注意    : W4 进入长模式后, 把 BITS 改成 64 即可自动切到 C 规则
# ============================================================

CROSS   ?= x86_64-elf-
AS      := $(CROSS)as
LD      := $(CROSS)ld
CC      := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy

QEMU    ?= qemu-system-x86_64

# ---- 架构位宽: W1-W3=32, W4 长模式后改 64 ----
BITS    ?= 32

BUILD   := build
KERNEL  := $(BUILD)/kernel.elf
ISO     := $(BUILD)/os.iso
ISO_DIR := iso

# 交叉版 grub-mkrescue 优先, 退化为宿主版
GRUB_MKRESCUE ?= $(shell command -v $(CROSS)grub-mkrescue 2>/dev/null || command -v grub-mkrescue 2>/dev/null)

# ---- 编译/链接参数 ----
ifeq ($(BITS),32)
  ASFLAGS     := --32
  LDFLAGS     := -m elf_i386
  CFLAGS_ARCH := -m32
else
  ASFLAGS     := --64
  LDFLAGS     := -m elf_x86_64
  CFLAGS_ARCH := -m64 -mcmodel=kernel
endif

# 裸机硬性要求, 少一个都会在后面出事:
#   -ffreestanding          不假设有标准库
#   -nostdlib -nostdinc     不链接/不搜索宿主库
#   -fno-stack-protector    没有 __stack_chk_fail 可用
#   -mno-red-zone           中断会踩坏 red zone
#   -fno-omit-frame-pointer 为了能栈回溯
#   -mgeneral-regs-only     内核不用 SSE, 简化上下文切换
CFLAGS := $(CFLAGS_ARCH) -std=gnu11 -O2 -g -Wall -Wextra \
          -ffreestanding -fno-stack-protector -fno-omit-frame-pointer \
          -mno-red-zone -mno-sse -mgeneral-regs-only \
          -nostdlib -nostdinc -Iinclude

ASM_SRCS := $(wildcard arch/x86_64/*.S)
C_SRCS   := $(wildcard kernel/*.c arch/x86_64/*.c drivers/*.c)
OBJS     := $(patsubst %.S,$(BUILD)/%.o,$(ASM_SRCS)) \
            $(patsubst %.c,$(BUILD)/%.o,$(C_SRCS))

.PHONY: all iso run debug clean check

all: $(ISO)

# ---------------- 编译 ----------------
$(BUILD)/%.o: %.S
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

# ---------------- 链接 ----------------
$(KERNEL): $(OBJS) linker.ld
	@mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -T linker.ld -nostdlib -o $@ $(OBJS)
	@echo "--- ELF 概览 ---"
	@$(CROSS)readelf -h $(KERNEL) | grep -E 'Class|Machine|Entry'
	@$(CROSS)readelf -l $(KERNEL) | grep -E 'LOAD|Entry'

# ---------------- 打包 ISO ----------------
$(ISO): $(KERNEL) $(ISO_DIR)/boot/grub/grub.cfg
	@mkdir -p $(ISO_DIR)/boot
	cp $(KERNEL) $(ISO_DIR)/boot/kernel.elf
	$(GRUB_MKRESCUE) -o $@ $(ISO_DIR)
	@echo "ISO 就绪: $@"

iso: $(ISO)

# ---------------- 运行 ----------------
run: $(ISO)
	$(QEMU) -cdrom $(ISO) -m 512M -no-reboot -no-shutdown -serial stdio

# 无窗口模式: 只看串口日志, 适合快速回归
run-headless: $(ISO)
	$(QEMU) -cdrom $(ISO) -m 512M -no-reboot -no-shutdown -display none -serial stdio

# 调试: 暂停等待 GDB 连接 (端口 1234)
debug: $(ISO)
	$(QEMU) -cdrom $(ISO) -m 512M -no-reboot -no-shutdown -serial stdio -s -S

# ---------------- 自检 ----------------
check:
	@ok=1; \
	for t in "$(AS)" "$(LD)" "$(CC)" "$(CROSS)readelf" "$(QEMU)" "$(GRUB_MKRESCUE)" xorriso; do \
	  if [ -n "$$t" ] && command -v "$$t" >/dev/null 2>&1; then \
	    printf "  [ok]      %s\n" "$$t"; \
	  else \
	    printf "  [MISSING] %s\n" "$$t"; ok=0; \
	  fi; \
	done; \
	if [ $$ok -eq 1 ]; then \
	  echo "环境就绪 (BITS=$(BITS))"; \
	else \
	  echo "缺失组件, 执行: brew install x86_64-elf-binutils x86_64-elf-gcc x86_64-elf-grub x86_64-elf-gdb xorriso"; \
	  exit 1; \
	fi

clean:
	rm -rf $(BUILD) $(ISO_DIR)/boot/kernel.elf
