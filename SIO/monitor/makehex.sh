#!/bin/bash

nasm -f bin v53sio_mon.asm -o v53sio_mon.bin -l v53sio_mon.lst
objcopy -I binary -O ihex --change-addresses=0x0000 v53sio_mon.bin v53sio_mon.hex

nasm -f bin v53sio_ram_mon.asm -o v53sio_ram_mon.bin -l v53sio_ram_mon.lst
objcopy -I binary -O ihex --change-addresses=0x0000 v53sio_ram_mon.bin v53sio_ram_mon.hex

cp v53sio_mon.hex v53sio_ram_mon.hex ~/Downloads/.