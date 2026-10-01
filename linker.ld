/* ============================================================
 *  linker.ld —— 内核链接脚本
 *
 *  关键点:
 *   1. .multiboot_header 必须排在文件最前面 (Multiboot2 要求它落在
 *      镜像前 32768 字节内, 且 8 字节对齐), 所以用 KEEP 且放第一个
 *   2. 加载地址 1MB (0x100000), 这是实模式/BIOS 保留区之上的安全位置
 *   3. __bss_start / __bss_end 供 boot.S 清零 .bss 使用
 * ============================================================ */

ENTRY(_start)

SECTIONS
{
    . = 1M;

    /* --- Multiboot2 头: 必须在最前 --- */
    .multiboot_header : ALIGN(8)
    {
        KEEP(*(.multiboot_header))
    }

    .text : ALIGN(16)
    {
        *(.text .text.*)
    }

    .rodata : ALIGN(16)
    {
        *(.rodata .rodata.*)
    }

    .data : ALIGN(16)
    {
        *(.data .data.*)
    }

    __bss_start = .;
    .bss : ALIGN(16)
    {
        *(.bss .bss.*)
        *(COMMON)
    }
    __bss_end = .;

    /* 丢弃不需要的段, 避免链接器警告 */
    /DISCARD/ :
    {
        *(.comment)
        *(.eh_frame)
        *(.note .note.*)
    }
}
