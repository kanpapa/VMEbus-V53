;----------------------------------------------------------------;
; MPSC 4CH Send loop Program
;----------------------------------------------------------------;
        ORG 0000h

; シリアルポートのIOアドレス
%define MPSC1_A_DATA 0x00A0
%define MPSC1_A_CTRL 0x00A2
%define MPSC1_B_DATA 0x00A4
%define MPSC1_B_CTRL 0x00A6
%define MPSC2_A_DATA 0x00A8
%define MPSC2_A_CTRL 0x00AA
%define MPSC2_B_DATA 0x00AC
%define MPSC2_B_CTRL 0x00AE

start:
        call mpsc_init
      
        mov bx, 0           ; ポートオフセット(0, 4, 8, 12...用)

ch_loop:
        mov cx, 100         ; 送信カウンタ

.send_block:
        ;--- 送信可能待ち ---
        lea dx, [bx + MPSC1_A_DATA + 2] ; status port (data + 2)
.wait_tx:
        in  al, dx
        test al, 04h
        jz  .wait_tx

        ;--- データ送信 ---
        sub dx, 2           ; data port (status - 2)
        mov al, 'A'         ; alを再ロード（inで破壊されるため）
        out dx, al

        loop .send_block

        ;--- 次のポートへ (a2, a6, aa, ae の差分は4) ---
        add bx, 4
        cmp bx, 16          ; 4ポート分(4*4=16) 終わったか
        jne ch_loop

        jmp start

; ---------------------------------------------------
; MPSC1/2 初期化シーケンス
; ---------------------------------------------------
mpsc_init:
; --- [Phase 1: Hardware Reset] ---
    mov dx, MPSC1_A_CTRL
    mov al, 0
    out dx, al          ; Pointer Reset 1
    out dx, al          ; Pointer Reset 2 

    mov dx, MPSC2_A_CTRL
    mov al, 0
    out dx, al          ; Pointer Reset 1 
    out dx, al          ; Pointer Reset 2 

    mov dx, MPSC1_B_CTRL
    mov al, 0
    out dx, al          ; Pointer Reset 1
    out dx, al          ; Pointer Reset 2 

    mov dx, MPSC2_B_CTRL
    mov al, 0
    out dx, al          ; Pointer Reset 1 
    out dx, al          ; Pointer Reset 2 

    ; Channel Reset (WR0: 0x18)
    mov dx, MPSC1_A_CTRL
    mov al, 0x18        ; Channel Reset command 
    out dx, al          ; Direct Write to WR0

    mov dx, MPSC2_A_CTRL
    mov al, 0x18
    out dx, al

    mov dx, MPSC1_B_CTRL
    mov al, 0x18        ; Channel Reset command 
    out dx, al          ; Direct Write to WR0

    mov dx, MPSC2_B_CTRL
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
    mov dx, MPSC1_A_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC1_A_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 2           ; 送信BRGレジスタセットモード有効
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC2_A_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC2_A_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 2           ; 送信BRGレジスタセットモード有効
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al

    mov dx, MPSC1_B_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC1_B_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 2           ; 送信BRGレジスタセットモード有効
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC2_B_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC2_B_CTRL
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
    mov dx, MPSC1_A_CTRL
    out dx, al          ; Write Index
    xchg al, bl
    out dx, al          ; Write Data
    xchg al, bl

    mov dx, MPSC2_A_CTRL
    out dx, al          ; Write Index
    xchg al, bl
    out dx, al          ; Write Data
    xchg al, bl

    ; MPSC2
    mov dx, MPSC1_B_CTRL
    out dx, al          ; Write Index
    xchg al, bl
    out dx, al          ; Write Data
    xchg al, bl

    mov dx, MPSC2_B_CTRL
    out dx, al          ; Write Index
    xchg al, bl
    out dx, al          ; Write Data
    xchg al, bl

    ret