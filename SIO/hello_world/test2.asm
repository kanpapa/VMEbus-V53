; ==========================================
; DVE-554 Analysis Test Code (NASM)
; ==========================================

[BITS 16]
[ORG 0x8100]

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
; MPSC1 初期化シーケンス (ROM 01:823B～の内容を網羅) 
; ---------------------------------------------------
L018238:
    mov dx, 0x00A2  ; MPSC1 Ch-A Control

    ; ポインタの強制リセット
    mov al, 0x00
    out dx, al
    out dx, al

    ; Channel Reset
    mov al, 0x18
    out dx, al
    
    ; リセット後の安定待ち
    mov cx, 100
.wait_res:
    nop
    nop
    nop
    loop .wait_res

    ; WR4: 64x Clock, 2 Stop, No Parity (ROM値: E0h)
    mov al, 0x04
    out dx, al
    mov al, 0xE0
    out dx, al

    ; WR10: NRZ Encoding (ROM値: 00h)
    mov al, 0x0A
    out dx, al
    mov al, 0x00
    out dx, al

    ; WR3: 8bit Rx, Rx Enable (ROM値: 32h)
    mov al, 0x03
    out dx, al
    mov al, 0x32
    out dx, al

    ; WR5: 8bit Tx, Tx Enable, DTR/RTS ON (ROM値: 68h相当)
    mov al, 0x05
    out dx, al
    mov al, 0x68
    out dx, al

    ; --- ボーレートジェネレータ設定 (ROM 01:82D0～付近) ---

    ; WR11: Clock Source Selection (ROM値: F3h)
    ; 受信・送信クロック共にBRG出力を選択
    mov al, 0x0B
    out dx, al
    mov al, 0xF3
    out dx, al

    ; WR12: Baud Rate Generator Time Constant Lower (ROM推測値)
    ; ダンプの 01:82A0 付近の設定に基づく
    mov al, 0x0C
    out dx, al
    mov al, 0x32    ; ROM内の設定値 32h
    out dx, al

    ; WR13: Baud Rate Generator Time Constant Upper
    mov al, 0x0D
    out dx, al
    mov al, 0x00
    out dx, al

    ; WR14: BRG Control - BRG Enable (ROM値: E6h)
    ; ここで物理的にカウントが開始されます
    mov al, 0x0E
    out dx, al
    mov al, 0xE6
    out dx, al

    ; --- 割り込みリセット (ROM 01:8321～) ---
    mov al, 0x80    ; Reset Tx Int
    out dx, al
    mov al, 0x40    ; Reset Rx Int
    out dx, al

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