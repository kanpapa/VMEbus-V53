#!/bin/bash

nasm -f bin hello_world_stackless.asm -o hello_world_stackless.bin -l hello_world_stackless.lst
objcopy -I binary -O ihex --change-addresses=0x0000 hello_world_stackless.bin hello_world_stackless.hex

cp hello_world_stackless.hex ~/Downloads/.