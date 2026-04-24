#!/bin/bash

nasm -f bin echo_back.asm -o echo_back.bin -l echo_back.lst
objcopy -I binary -O ihex --change-addresses=0x0000 echo_back.bin echo_back.hex

cp echo_back.hex ~/Downloads/.