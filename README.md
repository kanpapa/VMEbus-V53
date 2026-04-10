# VMEbus-V53

This repository contains documentation and sources for running DENSAN's V53 VME board DVE-V53/12.

## DVE-V53/12 CPU board

![DVE-V53/12](images/DVE-V53-12-board1.jpg)

Please refer to my blog for more information.  
https://kanpapa.com/2026/01/v53-vme-system-1.html

* Hardware test programs
  * [hello_world](hello_world)
    * A program to continuously send a single character to the serial port.
  * [echo_back](echo_back)
    * A program to perform a serial port echoback test.
  * [ram_test](ram_test)
    * A generic memory test program.
  * [set_timer](set_timer)
    * A V53 TCU test program.
  * [blink](blink)
    * A uPD71055 PPI test program.

* Monitor program
  * [monitor](monitor)
    * Monitor program for the V53 CPU.

* [images](images)
  * Board photos and images.

## DVE-554 SIO(Serial I/O) board

* [SIO/hello_world](SIO/hello_world)
  * DVE-554 Analysis Test Code.
* [SIO/monitor](SIO/monitor)
  * V53 ROM Monitor for DVE-554.

## V53 Applications

* [8086_NASCOM_BASIC](https://github.com/kanpapa/8086_NASCOM_BASIC)
  * NASCOM BASIC. Converted source code from 8080/Z80 to 8086

* [ELKS](https://github.com/kanpapa/elks)
  * Embeddable Linux Kernel Subset - Linux for 8086

## Disclaimer
The contents of this repository are the result of personal research and are provided "as is" without any warranty.
