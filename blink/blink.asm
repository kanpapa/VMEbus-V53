;==========================================================
; V53 PPI Port A Blink (L-Chika)
; Port: 00E0h (Port A)
; Ctrl: 00E6h
;==========================================================
bits 16
org 0x1000

PORT_A      equ 0x00E0
PORT_CTRL   equ 0x00E6

Start:
    ; 1. PPI初期化 (Mode 0, All Output)
    ;    1000 0000 b = 80h
    mov  dx, PORT_CTRL
    mov  al, 0x80
    out  dx, al

Loop:
    ; 2. 点灯 (FFh)
    mov  dx, PORT_A
    mov  al, 0xff
    out  dx, al

    CALL Delay         ; 待つ

    ; 3. 消灯 (00h)
    mov  al, 0x00
    out  dx, al

    call Delay         ; 待つ

    jmp  Loop

;--- ウェイトルーチン (二重ループ) ---
Delay:
    push bx             ; レジスタ退避
    push cx

    mov  bx, 0x0020     ; 外側ループ回数 (約32回)

Delay_Outer:
    mov  cx, 0x0000     ; 内側ループ (0指定で65536回回ります)
    
Delay_Inner:
    nop                 ; 時間稼ぎ
    loop Delay_Inner    ; CXを減らしてループ (V53はここが高速)

    dec  bx             ; 外側カウンタを減らす
    jnz  Delay_Outer    ; BXが0になるまで繰り返す

    pop  cx             ; レジスタ復帰
    pop  bx
    ret