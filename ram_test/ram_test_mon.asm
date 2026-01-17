; =================================================================
; V53 Memory Test v2 for V53 MONITOR
; =================================================================
    cpu 186
    bits 16
    
section .text
    org 0

    ; --- 設定 ---
    %define SCU_DATA    0x01260
    %define SCU_SST     0x01261
    %define TX_READY    0x01
    
    ; テスト対象アドレス
    %define TEST_SEG    0x3000 

    ; モニタの再起動アドレス (ROMの先頭)
    %define MON_BOOT    0xE000:0000

entry:
    ; --- 初期化 ---
    push ds
    push es
    mov ax, cs
    mov ds, ax

    mov si, msg_start
    call puts

    ; --- テスト準備 ---
    mov ax, TEST_SEG
    mov es, ax
    xor di, di

    ; --- パターン 0x55 ---
test_55:
    mov al, 0x55
    call run_test_byte
    jc error_found

    ; --- パターン 0xAA ---
test_aa:
    mov al, 0xAA
    call run_test_byte
    jc error_found

    ; --- 成功 ---
    mov si, msg_pass
    call puts
    jmp exit_prog

; -----------------------------------------------------------------
; Subroutine: 指定パターンの書き込み・検証
; -----------------------------------------------------------------
run_test_byte:
    mov cx, 0       ; Loop 64KB
    xor di, di      ; Reset Offset

.write_loop:
    mov [es:di], al ; 書き込み
    inc di
    loop .write_loop

    ; 検証フェーズ
    mov cx, 0
    xor di, di
    
    ; dotを出力
    push ax
    call put_dot
    pop ax
    
.verify_loop:
    mov bl, [es:di] ; 読み出し
    cmp bl, al      ; AL(0x55) と比較
    jne .verify_err ; 不一致ならエラーへ

    inc di
    loop .verify_loop

    clc             ; CF=0 Success
    ret

.verify_err:
    stc             ; CF=1 Error
    ret

; エラー表示ルーチン
error_found:
    push ax
    push bx
    call putc_crlf
    
    mov si, msg_err     ; エラー表示
    call puts
    
    mov ax, es          ; esを16進数で表示
    call print_hex_word
    
    mov al, ':'         ; セパレーターを表示
    call putc
    
    mov ax, di          ; diを表示
    call print_hex_word
    
    mov si, msg_write   ; W: を表示
    call puts
    
    pop bx
    pop ax
    push bx
    call print_hex_byte ; 書き込んだデータを表示
    
    mov si, msg_read    ; R: を表示
    call puts
    
    pop bx
    mov al, bl
    call print_hex_byte ; 読みだしたデータを表示
    call putc_crlf
    ; fall through to exit

exit_prog:
    pop es
    pop ds

    ; モニタへ戻るためのジャンプ
    jmp MON_BOOT

; --- Utilities ---
puts:
    mov al, [si]
    or al, al
    jz .ret
    call putc
    inc si
    jmp puts
.ret: ret

put_dot:
    mov al, '.'
    call putc
    ret

putc:
    push dx
    push ax
    mov dx, SCU_SST
.w: in al, dx
    test al, TX_READY
    jz .w
    mov dx, SCU_DATA
    pop ax
    push ax
    out dx, al
    pop ax
    pop dx
    ret

putc_crlf:
    mov al, 0x0D
    call putc
    mov al, 0x0A
    jmp putc

print_hex_word:
    push ax
    mov al, ah
    call print_hex_byte
    pop ax
print_hex_byte:
    push ax
    push cx
    push ax
    shr al, 4
    call .digit
    pop ax
    and al, 0x0F
    call .digit
    pop cx
    pop ax
    ret
.digit:
    add al, '0'
    cmp al, '9'
    jbe .p
    add al, 7
.p: call putc
    ret

; --- Data ---
msg_start: db "MemTest...", 0
msg_pass:  db " Pass!", 0x0D, 0x0A, 0
msg_err:   db "Err ", 0
msg_write: db " W:", 0
msg_read:  db " R:", 0