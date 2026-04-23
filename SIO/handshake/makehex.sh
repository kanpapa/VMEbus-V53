#!/bin/bash

nasm -f bin master_cpu.asm -o master_cpu.bin -l master_cpu.lst
nasm -f bin slave_sio.asm -o slave_sio.bin -l slave_sio.lst
objcopy -I binary -O ihex --change-addresses=0x0000 master_cpu.bin master_cpu.hex
objcopy -I binary -O ihex --change-addresses=0x0000 slave_sio.bin slave_sio.hex
cp master_cpu.hex slave_sio.hex ~/Downloads/.
