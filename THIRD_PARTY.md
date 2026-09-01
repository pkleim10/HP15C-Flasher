# Third-party notices

HP 15C Flasher is a Mach II Labs product. It does not include HP firmware.

## SAM-BA SAM4L flash applet

This app embeds `applet-flash-sam4l4.bin` (2,652 bytes), the SRAM flash
helper from Atmel SAM-BA 2.16 (`tcl_lib/at91sam4l-ek/`). The host loads it
into calculator RAM for the duration of a write; it is not stored in
application flash and is not HP Voyager firmware.

Copyright (c) 2011–2012, Atmel Corporation. All rights reserved.

Redistributed under the SAM Software Package License (below). Atmel’s name
is not used to endorse or promote this product.

Mach II Labs is not affiliated with Atmel, Microchip, or HP.

### SAM Software Package License

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice,
  this list of conditions and the disclaimer below.

Atmel's name may not be used to endorse or promote products derived from
this software without specific prior written permission.

DISCLAIMER: THIS SOFTWARE IS PROVIDED BY ATMEL "AS IS" AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT ARE
DISCLAIMED. IN NO EVENT SHALL ATMEL BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
