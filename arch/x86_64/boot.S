/* ============================================================
 *  arch/x86_64/boot.S —— Multiboot2 入口 (32 位保护模式)
 *
 *  GRUB 交付时的机器状态:
 *    eax = 0x36D76289   multiboot2 magic
 *    ebx = 32 位物理地址, 指向 multiboot2 information 结构
 *    cs  = 32 位代码段, 保护模式已开启
 *    分页 = 关闭, 中断 = 关闭, 段寄存器 = flat (0..4GB)
 *
 *  本阶段 (W1-W3) 只做三件事:
 *    1. 建立自己的栈并清零 .bss (不依赖 bootloader)
 *    2. 往串口 COM1 与 VGA 显存各打一行字 —— 证明工具链全线贯通
 *    3. 停机
 *  长模式与 C 运行时是 W4 的任务。
 * ============================================================ */

.set MB2_MAGIC,     0xE85250D6
.set MB2_ARCH_I386, 0

/* ---------------- Multiboot2 头 ---------------- */
.section .multiboot_header, "a"
.align 8
mb2_header_start:
    .long MB2_MAGIC
    .long MB2_ARCH_I386
    .long mb2_header_end - mb2_header_start
    .long -(MB2_MAGIC + MB2_ARCH_I386 + (mb2_header_end - mb2_header_start))

    /* 信息请求标签: 向 bootloader 索要 memory map(6) 与 framebuffer(8) */
    .align 8
    .short 1
    .short 0
    .long 16
    .long 6
    .long 8

    /* 结束标签: type=0, flags=0, size=8 */
    .align 8
    .short 0
    .short 0
    .long 8
mb2_header_end:

/* ---------------- 32 位入口 ---------------- */
.section .text
.global _start
.type _start, @function
.code32
_start:
    cli                     /* 中断关闭, 后面由我们自己开 */
    cld                     /* 串口/内存操作正向 */

    /* 1) 清零 .bss —— 栈也在这里面, 此刻还没用它 */
    movl $__bss_start, %edi
    movl $__bss_end, %ecx
    subl %edi, %ecx
    xorl %eax, %eax
    rep stosb

    /* 2) 建立自己的内核栈 */
    movl $stack_top, %esp
    movl $stack_top, %ebp

    /* 3) 保存 multiboot2 交付的 magic 与 info 指针 (必须在清 .bss 之后) */
    movl %eax, mb2_magic
    movl %ebx, mb2_info

    /* 4) 初始化串口并输出 */
    call serial_init
    movl $msg_boot, %esi
    call serial_puts
    movl $vga_msg, %esi
    call vga_puts

    /* 5) 校验 bootloader magic */
    cmpl $0x36D76289, mb2_magic
    jne .Lbad_magic
    movl $msg_magic_ok, %esi
    call serial_puts
    jmp .Lhang

.Lbad_magic:
    movl $msg_bad_magic, %esi
    call serial_puts

.Lhang:
    cli
    hlt
    jmp .Lhang
.size _start, . - _start

/* ============================================================
 *  串口 COM1 = 0x3F8, 115200 8N1
 * ============================================================ */
.type serial_init, @function
serial_init:
    movw $0x3F8 + 1, %dx
    movb $0x00, %al
    outb %al, %dx           /* 关闭串口中断 */
    movw $0x3F8 + 3, %dx
    movb $0x80, %al
    outb %al, %dx           /* 打开 DLAB, 准备设置波特率 */
    movw $0x3F8 + 0, %dx
    movb $0x01, %al
    outb %al, %dx           /* 除数低字节 = 1 -> 115200 */
    movw $0x3F8 + 1, %dx
    movb $0x00, %al
    outb %al, %dx           /* 除数高字节 */
    movw $0x3F8 + 3, %dx
    movb $0x03, %al
    outb %al, %dx           /* 8 位数据, 无校验, 1 停止位 */
    movw $0x3F8 + 2, %dx
    movb $0xC7, %al
    outb %al, %dx           /* 使能 FIFO, 清空, 14 字节触发 */
    movw $0x3F8 + 4, %dx
    movb $0x0B, %al
    outb %al, %dx           /* IRQ 使能, RTS/DSR */
    ret
.size serial_init, . - serial_init

/* 发送单字符, 字符在 %al */
.type serial_putc, @function
serial_putc:
    pushl %edx
    pushl %eax              /* 先存下要发的字符 */
1:
    movw $0x3F8 + 5, %dx
    inb %dx, %al
    testb $0x20, %al        /* LSR bit5: 发送保持寄存器空 */
    jz 1b
    popl %eax
    movw $0x3F8, %dx
    outb %al, %dx
    popl %edx
    ret
.size serial_putc, . - serial_putc

/* 输出 NUL 结尾字符串, 地址在 %esi */
.type serial_puts, @function
serial_puts:
    pushl %eax
    pushl %esi
1:
    lodsb
    testb %al, %al
    jz 2f
    call serial_putc
    jmp 1b
2:
    popl %esi
    popl %eax
    ret
.size serial_puts, . - serial_puts

/* ============================================================
 *  VGA 文本模式显存 0xB8000, 每字符 2 字节 (ASCII + 属性)
 *  W3 的任务是把它重构成带滚屏的 terminal 抽象
 * ============================================================ */
.type vga_puts, @function
vga_puts:
    pushl %edi
    pushl %eax
    pushl %esi
    movl $0xB8000, %edi
    movb $0x0F, %ah         /* 属性: 黑底白字 */
1:
    lodsb
    testb %al, %al
    jz 2f
    movb %al, (%edi)
    movb %ah, 1(%edi)
    addl $2, %edi
    jmp 1b
2:
    popl %esi
    popl %eax
    popl %edi
    ret
.size vga_puts, . - vga_puts

/* ============================================================
 *  只读数据 / 未初始化数据
 * ============================================================ */
.section .rodata
msg_boot:      .asciz "[os] GRUB handoff OK, we are alive in 32-bit protected mode\n"
msg_magic_ok:  .asciz "[os] multiboot2 magic verified (0x36D76289)\n"
msg_bad_magic: .asciz "[os] BAD multiboot2 magic: not booted by a MB2 bootloader\n"
vga_msg:       .asciz "Hello from kernel!"

.section .bss
.align 4
.global mb2_magic
mb2_magic:     .space 4
.global mb2_info
mb2_info:      .space 4

.align 16
stack_bottom:  .space 16384          /* 16 KiB 内核栈 */
.global stack_top
stack_top:
