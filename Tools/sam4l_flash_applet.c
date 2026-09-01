/*
 * FLASHCALW helper for ATSAM4LC2C. Loaded at 0x20001000, entered at 0x20001001.
 *
 * Mailbox 0x20001F00: cmd (1=unlock, 2=write page), page, status (LOCKE|PROGE).
 * Page buffer 0x20002000 (512 bytes) for cmd 2.
 *
 * Rebuild .text into FlashApplet.swift:
 *   clang -target thumbv7em-unknown-none-eabi -mcpu=cortex-m4 -mthumb -Os \
 *     -ffreestanding -nostdlib -fPIC -c Tools/sam4l_flash_applet.c -o /tmp/applet.o
 */

typedef unsigned int u32;

#define FCMD (*(volatile u32 *)0x400A0004u)
#define FSR (*(volatile u32 *)0x400A0008u)
#define MAIL_CMD (*(volatile u32 *)0x20001F00u)
#define MAIL_PAGE (*(volatile u32 *)0x20001F04u)
#define MAIL_STATUS (*(volatile u32 *)0x20001F08u)
#define PAGEBUF ((volatile u32 *)0x20002000u)

#define KEY 0xA5000000u
#define FRDY 1u
#define ERR ((1u << 2) | (1u << 3))

void applet(void)
{
    u32 cmd = MAIL_CMD;
    u32 page = MAIL_PAGE;
    if (cmd == 1u) {
        while ((FSR & FRDY) == 0) {
        }
        FCMD = KEY | ((page & 0xFFFFu) << 8) | 5u;
        while ((FSR & FRDY) == 0) {
        }
        MAIL_STATUS = FSR & ERR;
    } else if (cmd == 2u) {
        while ((FSR & FRDY) == 0) {
        }
        FCMD = KEY | ((page & 0xFFFFu) << 8) | 2u;
        while ((FSR & FRDY) == 0) {
        }
        while ((FSR & FRDY) == 0) {
        }
        FCMD = KEY | 3u;
        while ((FSR & FRDY) == 0) {
        }
        volatile u32 *dst = (volatile u32 *)(page << 9);
        u32 i;
        for (i = 0; i < 128u; i++) {
            dst[i] = PAGEBUF[i];
        }
        while ((FSR & FRDY) == 0) {
        }
        FCMD = KEY | ((page & 0xFFFFu) << 8) | 1u;
        while ((FSR & FRDY) == 0) {
        }
        MAIL_STATUS = FSR & ERR;
    } else {
        MAIL_STATUS = 0xFFFFFFFFu;
    }
    MAIL_CMD = 0;
}
