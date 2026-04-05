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
; MPSC1/2 初期化シーケンス (ROMはBisyncだったのでAsyncに変更）
; ---------------------------------------------------
L018238:
; --- [Phase 1: Hardware Reset] ---
    mov dx, MPSC1_CTRL
    mov al, 0
    out dx, al          ; Pointer Reset 1
    out dx, al          ; Pointer Reset 2 

    mov dx, MPSC2_CTRL
    mov al, 0
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

    ; CR2: 割り込み動作の基本設定
    mov al, 2
    mov bl, 0x00        ; 割り込みは使用しない。ポーリングモード。
    call mpsc_write_both

    ; CR4: 通信プロトコルとデータフォーマットの設定
    mov al, 4
    mov bl, 0x44        ; x16, Async, ストップビット 1bit，パリティなし
    call mpsc_write_both

    ; CR1: 送受信割り込みおよびDMAの無効化
    mov al, 1
    mov bl, 0x00
    call mpsc_write_both
    
    ; CR12: ボーレートジェネレータ（BRG）の割り込みとレジスタ書き込み設定 
    mov dx, MPSC1_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC1_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 2           ; 送信BRGレジスタセットモード有効
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC2_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC2_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 2           ; 送信BRGレジスタセットモード有効
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al

    ; CR15: クロックソースとピン機能の選択
    mov al, 15
    mov bl, 0x56        ; ボーレートジェネレータ使用
    call mpsc_write_both

    ; CR14: BRGの動作許可とソース設定
    mov al, 14
    mov bl, 0x07        ; BRGを動作させるソースクロックとして、システムクロック（CLK）を選択,送受信BRGカウント有効
    call mpsc_write_both

    ; CR10: データエンコーディングなどの設定
    mov al, 10
    mov bl, 0x00        ; データフォーマットとしてNRZ方式を選択
    call mpsc_write_both

    ; CR3: 受信動作の有効化
    mov al, 3
    mov bl, 0xC1        ; データ 8bit，受信イネーブル
    call mpsc_write_both
    
    ; CR5: 送信動作の有効化とモデム制御ピンのアサート
    mov al, 5
    mov bl, 0xEA        ; データ 8bit，送信イネーブル
    call mpsc_write_both
    
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