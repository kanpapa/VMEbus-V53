#!/bin/bash

nasm -f bin blink.asm -o blink.bin -l blink.lst
objcopy -I binary -O ihex --change-addresses=0x0000 blink.bin blink.hex

cp blink.hex ~/Downloads/.