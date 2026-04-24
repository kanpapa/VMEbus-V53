#!/bin/bash

nasm -f bin test2.asm -o test2.bin -l test2.lst
objcopy -I binary -O ihex --change-addresses=0x0000 test2.bin test2.hex
cp test2.hex  ~/Downloads/.