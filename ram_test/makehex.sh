#!/bin/bash

nasm -f bin ram_test_mon.asm -o ram_test_mon.bin -l ram_test_mon.lst
objcopy -I binary -O ihex --change-addresses=0x0000 ram_test_mon.bin ram_test_mon.hex

nasm -f bin ram_test_stackless.asm -o ram_test_stackless.bin -l ram_test_stackless.lst
objcopy -I binary -O ihex --change-addresses=0x0000 ram_test_stackless.bin ram_test_stackless.hex

cp ram_test_mon.hex ram_test_stackless.hex ~/Downloads/.