; CPU Board (Master) Side
; 1300h(Write): Register A (LED Switch) / 1300h(Read): Register B (SIO Status)

        ORG 0h

START:
        MOV DX, 1300h
        ; --- LED点灯 ＋ 処理要求 ---
        MOV AL, 081h        
        OUT DX, AL
        ; ちょっと待つ
        mov cx, 0ffffh
        loop $
        
        ; --- SIO側の完了報告(レジスタB)を待つ ---
        ; 何か値が書き込まれたら(00h以外になったら)次へ進む
WAIT_DONE:
        IN  AL, DX
        OR  AL, AL          ; 00h かどうかチェック
        JZ  WAIT_DONE       ; 00h の間はループ

        ; --- 完了を確認したのでLED消灯 ---
        MOV AL, 00h
        OUT DX, AL
        ; ちょっと待つ
        mov cx, 0ffffh
        loop $

        ; --- SIO側がフラグを下ろすのを待つ ---
WAIT_ACK:
        IN  AL, DX
        OR  AL, AL
        JNZ WAIT_ACK        ; 00h に戻るまで待機

        ; 肉眼確認用のウェイト
        call Delay

        JMP START

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