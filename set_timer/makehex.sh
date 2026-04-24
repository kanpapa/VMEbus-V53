#!/bin/bash

nasm -f bin set_timer.asm -o set_timer.bin -l set_timer.lst
objcopy -I binary -O ihex --change-addresses=0x0000 set_timer.bin set_timer.hex

cp set_timer.hex ~/Downloads/.