; SIO Board (Slave) Side
; 0080h(Read): Register A (Host Cmd/LED) / 0080h(Write): Register B (Status)

        ORG 0h
MAIN:
        MOV DX, 0080h

        ; --- STEP 1: LED(Bit 7)が点灯したか「だけ」を見る ---
WAIT_REQ:
        IN  AL, DX          ; レジスタAを読み出し
        TEST AL, 80h        ; Bit 7 が立っているか？
        JZ  WAIT_REQ        ; 0の間はループ

        ; --- STEP 2: SIOボード側の処理 (ここでは単にウェイト) ---
        call Delay          ; ここで少し待つ
        
        ; --- STEP 3: 処理完了を報告 (レジスタB) ---
        ; ホストに「読めたよ！」と伝えるために 01h などを書く
        MOV AL, 01h         
        OUT DX, AL
        ; ちょっと待つ
        mov cx, 0ffffh
        loop $

        ; --- STEP 4: ホストがLEDを消灯(Bit 7 -> 0)させるのを待つ ---
WAIT_CLR:
        IN  AL, DX
        TEST AL, 80h        ; Bit 7 が 0 になるのを待つ
        JNZ WAIT_CLR        ; 1の間はループ

        ; --- STEP 4: 完了フラグを下ろす ---
        MOV AL, 00h
        OUT DX, AL
        ; ちょっと待つ
        mov cx, 0ffffh
        loop $

        JMP MAIN

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