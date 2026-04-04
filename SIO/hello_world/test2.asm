; ==========================================
; DVE-554 Analysis Test Code (NASM)
; ==========================================

[BITS 16]
[ORG 0x8100]

%define MPSC1_CTRL 0x00A2
%define MPSC2_CTRL 0x00AA

START:
    cli                     ; 割り込み禁止
    cld                     ; 文字列処理を前方へ
    mov     sp, 0x7FFF      ; SP = 0x7FFF 初期化
    mov     ax, 0x0000
    mov     ds, ax          ; DS = 0000h
    mov     ax, 0xC000
    mov     es, ax          ; ES = C000h

    ; --- 2. V53 システムレジスタ初期化 (ROM 01:81E6ルーチンの再現) ---
    call L0181E6

    ; --- 3. TCU (タイマーユニット) 初期化 (ROM 01:839Dルーチンの再現) ---
    call L01839D

    ; --- 4. 物理IOの初期化 (ROM 01:83FDルーチンの内容) ---
    call L0183FD

    ; --- 5. MPSC の初期化 ---
    call L018238            ; 外部MPSC uPD72001のセットアップ

    ; --- 6. 文字 'A' の連続送信 ---
.loop_send:
    mov dx, 0x00A2
.wait_tx:
    in al, dx
    test al, 0x04   ; Tx Buffer Empty?
    jz .wait_tx
    mov dx, 0x00A0
    mov al, 'A'
    out dx, al
    jmp .loop_send

; --------------------------------------------------
;  V53 システムレジスタ初期化 (ROM 01:81E6相当)
; --------------------------------------------------
L0181E6:
    mov si, TABLE_V53_REG
.next:
    mov dx, [cs:si]      ; Port Number (16bit)
    cmp dx, 0xFFFF       ; Terminator
    je .done
    mov al, [cs:si+2]    ; Value (8bit)
    out dx, al
    add si, 3
    jmp .next
.done:
    ret

; --------------------------------------------------
; TCU (タイマーユニット) 初期化 (ROM 01:839D相当)
; --------------------------------------------------
L01839D:
    mov si, TABLE_TCU_REG
.next:
    mov dx, [cs:si]      ; Port1 (16bit)
    cmp dx, 0xFFFF       ; Terminator
    je .done
    mov al, [cs:si+2]    ; Val1 (8bit)
    out dx, al
    mov dx, [cs:si+3]    ; Port2 (16bit)
    mov ax, [cs:si+5]    ; Val2 (16bit)
    out dx, al           ; Port2 Low
    mov al, ah
    out dx, al           ; Port2 High
    add si, 7
    jmp .next
.done:
    ret

; ---------------------------------------------------
; 物理IOの初期化 (ROM 01:83FDルーチンの内容) 
; ---------------------------------------------------
L0183FD:
    mov al, 0x00
    mov dx, 0x0086
    out dx, al
    mov dx, 0x0082
    out dx, al
    mov dx, 0x0080
    out dx, al
    ret

; ---------------------------------------------------
; MPSC1 初期化シーケンス (ROM 01:8238～の内容を網羅) 
; ---------------------------------------------------
L018238:
; --- [Phase 1: Hardware Reset] ---
    mov dx, MPSC1_CTRL
    xor al, al          ; AL = 0
    out dx, al          ; Pointer Reset 1 
    out dx, al          ; Pointer Reset 2 

    mov dx, MPSC2_CTRL
    out dx, al          ; Pointer Reset 1 
    out dx, al          ; Pointer Reset 2 

    ; Channel Reset (WR0: 0x18)
    mov dx, MPSC1_CTRL
    mov al, 0x18        ; Channel Reset command 
    out dx, al          ; Direct Write to WR0

    mov dx, MPSC2_CTRL
    mov al, 0x18
    out dx, al
    
    ; リセット後の安定待ち
    mov cx, 100
.wait_res:
    nop
    nop
    nop
    loop .wait_res

    ; WR1: Reset Ext/Status
    mov al, 0x01        ; Select WR1
    mov bl, 0x10        ; Value 
    call mpsc_write_both

    ; WR2: 
    mov al, 0x02        ; Select WR2
    mov bl, 0xE0        ; Value 
    call mpsc_write_both

    ; WR4:
    mov al, 0x04        ; Select WR4
    mov bl, 0x10        ; Value 
    call mpsc_write_both

    ; WR4: 2回目
    mov al, 0x04        ; Select WR4
    mov bl, 0x10        ; Value 
    call mpsc_write_both

    ; WR6:
    mov al, 0x06        ; Select WR6
    mov bl, 0x32        ; Value 
    call mpsc_write_both

    ; WR7:
    mov al, 0x07        ; Select WR7
    mov bl, 0x32        ; Value 
    call mpsc_write_both

    ; WR12:
    mov al, 0x0C
    mov bl, 0x00
    call mpsc_write_both
    
    ; WR14:
    mov al, 0x0E        ; Select WR14
    mov bl, 0x00        ; Value 
    call mpsc_write_both

    ; WR15:
    mov al, 0x0F        ; Select WR15
    mov bl, 0x05        ; Value 
    call mpsc_write_both

    ; WR11:
    mov al, 0x0B        ; Select WR11
    mov bl, 0x00        ; Value 
    call mpsc_write_both

    ; WR3:
    mov al, 0x03        ; Select WR3
    mov bl, 0xF3        ; Value 
    call mpsc_write_both

    ; WR5:
    mov al, 0x05        ; Select WR5
    mov bl, 0xE6        ; Value
    call mpsc_write_both
    
    ; Reset Tx/Rx Interrupt (WR0)
    mov dx, MPSC1_CTRL
    mov al, 0x80        ; Reset Tx Int 
    out dx, al
    mov al, 0x40        ; Reset Rx Int 
    out dx, al

    ret

; --- Helper: Write to both MPSC1 and MPSC2 ---
; Input: AL = Register Index, BL = Value
mpsc_write_both:
    ; MPSC1
    mov dx, MPSC1_CTRL
    out dx, al          ; Write Index
    xchg al, bl
    out dx, al          ; Write Data
    xchg al, bl
    
    ; MPSC2
    mov dx, MPSC2_CTRL
    out dx, al          ; Write Index
    xchg al, bl
    out dx, al          ; Write Data
    xchg al, bl
    ret

; --------------------------------------------------
; V53システムレジスタ設定テーブル (ROM 01:81FCから完全抽出)
; --------------------------------------------------
ALIGN 2
TABLE_V53_REG:
    db 0xFE, 0xFF, 0x00     ; FFFE (SCTL) = 00h
    db 0xFD, 0xFF, 0x06     ; FFFD (OPSEL)= 06h
    db 0xFC, 0xFF, 0x00     ; FFFC (OPHA) = 00h
    db 0xFB, 0xFF, 0xE0     ; FFFB (DULA) = E0h
    db 0xFA, 0xFF, 0xC0     ; FFFA (IULA) = C0h
    db 0xF9, 0xFF, 0xD0     ; FFF9 (TULA) = D0h
    db 0xF8, 0xFF, 0xF0     ; FFF8 (SULA) = F0h
    db 0xEA, 0xFF, 0x00     ; FFEA (WMB0) = 00h
    db 0xEB, 0xFF, 0x00     ; FFEB (WCY1) = 00h
    db 0xEC, 0xFF, 0x00     ; FFEC (WCY0) = 00h
    db 0xF3, 0xFF, 0x73     ; FFF3 (WMB1) = 73h
    db 0xED, 0xFF, 0x00     ; FFED (WAC)  = 00h
    db 0xF4, 0xFF, 0x10     ; FFF4 (WCY2) = 10h
    db 0xF5, 0xFF, 0x22     ; FFF5 (WCY3) = 22h
    db 0xF6, 0xFF, 0x10     ; FFF6 (WCY4) = 10h
    db 0xF2, 0xFF, 0x00     ; FFF2 (RFC)  = 00h
    db 0xE9, 0xFF, 0x00     ; FFE9 (BRC)  = 00h
    db 0xF0, 0xFF, 0x02     ; FFF0 (TCKS) = 02h
    db 0xF1, 0xFF, 0x00     ; FFF1 (SBCR) = 00h
    db 0xFF, 0xFF, 0xFF     ; 終端マーカー

; --------------------------------------------------
; TCU タイマー設定テーブル (ROM 01:83BFから完全抽出)
; --------------------------------------------------
ALIGN 2
TABLE_TCU_REG:
    ; Port1, Val1, Port2, Val2(16)
    db 0xD6, 0x00, 0x36, 0xD0, 0x00, 0x20, 0x4E ; T0設定
    db 0xD6, 0x00, 0x70, 0xD2, 0x00, 0x05, 0x0D ; T0最大値A
    db 0xD6, 0x00, 0xB0, 0xD4, 0x00, 0x05, 0x0D ; T0最大値B
    db 0xFF, 0xFF           ; 終端マーカー