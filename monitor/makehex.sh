#!/bin/bash

nasm -f bin v53mon.asm -o v53mon.bin -l v53mon.lst
objcopy -I binary -O ihex --change-addresses=0x0000 v53mon.bin v53mon.hex

nasm -f bin v53_ram_mon.asm -o v53_ram_mon.bin -l v53_ram_mon.lst
objcopy -I binary -O ihex --change-addresses=0x0000 v53_ram_mon.bin v53_ram_mon.hex

cp v53mon.hex v53_ram_mon.hex ~/Downloads/.