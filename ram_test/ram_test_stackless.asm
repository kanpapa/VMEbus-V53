; =================================================================
; DENSAN V53 VME board "RAM TEST" test ROM
; =================================================================

; ▼▼▼ ROMサイズ設定 (ここを環境に合わせる) ▼▼▼
%define ROM_SIZE_1024  0x20000  ; 27C010 (128KB)
; 使用するROMサイズを選択
%define ROM_TOTAL     ROM_SIZE_1024
; ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

; ==========================================
; V53 System Register
; ==========================================
%define SCTL    0x0FFFE ; システム・コントロール・レジスタ
%define OPSEL   0x0FFFD ; 内蔵ペリフェラル選択レジスタ
%define OPHA    0x0FFFC ; 内蔵ペリフェラル・リロケーション・レジスタ
%define DULA    0x0FFFB ; 
%define IULA    0x0FFFA ; 
%define TULA    0x0FFF9 ; 
%define SULA    0x0FFF8 ; SCUリロケーション・レジスタ 
%define WCY4    0x0FFF6 ; 
%define WCY3    0x0FFF5 ; 
%define WCY2    0x0FFF4 ; 
%define WMB1    0x0FFF3 ; 
%define RFC     0x0FFF2 ; 
%define SBCR    0x0FFF1 ; 
%define TCKS    0x0FFF0 ; 
%define WAC     0x0FFED ; 
%define WCY0    0x0FFEC ; 
%define WCY1    0x0FFEB ; 
%define WMB0    0x0FFEA ; 
%define BRC     0x0FFE9 ; ボー・レート・カウンタ
%define BADR    0x0FFE1 ; 
%define BSEL    0x0FFE0 ; 
%define XAM     0x0FF80 ; 
%define PGR     0x0FF00 ; 

; SCUレジスタ (SCUは1260Hに配置）
%define SCU_DATA 0x01260 ; 送受データ・レジスタ(R:SRB/W:STB)
%define SCU_SST  0x01261 ; ステータス・レジスタ(R:SST)
%define SCU_SCM  0x01261 ; コマンドレジスタ(W:SCM)
%define SCU_SMD  0x01262 ; シリアルモード設定(W:SMD)
%define SCU_SIMK 0x01263 ; シリアル割り込みマスクレジスタ(R/W:SIMK)

cpu 186
bits 16

; ==========================================
; コードセクション (ROMの先頭付近)
; ==========================================
section .text
org 0

; -----------------------------------------------------------------
; Entry Point (Offset 0x0000)
; -----------------------------------------------------------------
start:
    cli             ; 割り込み禁止

    ; ---------------------------------------------
    ; 1. セグメントレジスタ初期化
    ; ※CSはJMP命令で設定されるので、DS/ES/SSを設定する
    ; ---------------------------------------------
    mov ax, 0x0000
    mov ds, ax      ; DS (Data Segment) を0000Hに設定し、ここをテスト対象とする
    mov es, ax
    ;mov ss, ax     ; スタックは使わない
    ;mov sp, 0
    
    ; ---------------------------------------------
    ; 2. システム・コントロール・レジスタ (SCTL) の設定
    ; ビット4 (SC) = 1 : 内蔵BRGを使用
    ; ビット0 (IOAG) = 1 : 8ビット・バウンダリ（連続配置）
    ; ---------------------------------------------
    mov dx, SCTL
    mov al, 00010001b
    out dx, al

    ; ---------------------------------------------
    ; 3. ボーレートジェネレータ (BRG) の設定
    ;  38400bps設定 (fx=16MHz, factor=x16)
    ;  16,000,000/(16×38400) ≈ 26
    ; ---------------------------------------------
    mov dx, BRC
    mov al, 26
    out dx, al

    ; ---------------------------------------------
    ; 4. IOアドレスの設定 (0x1260にSCUを配置)
    ; OPHA (FFFCH) に 12H を設定 (ベースアドレス上位8ビット)
    ; SULA (FFF8H) に 60H を設定 (SCUのオフセット)
    ; ---------------------------------------------
    mov dx, OPHA
    mov al, 0x12    ; 上位アドレス
    out dx, al

    mov dx, SULA
    mov al, 0x60    ; 下位アドレス
    out dx, al
    
    ; ---------------------------------------------
    ; 5. 内蔵周辺選択レジスタ (OPSEL) でSCUを有効化
    ; ビット3 (SS) = 1 : SCUの使用を許可
    ; ---------------------------------------------
    mov dx, OPSEL
    mov al, 00001000b   ; Bit3 (SS): SCUの使用を許可
    out dx, al

    ; ---------------------------------------------
    ; 6. SCU内部レジスタの初期化 (配置した1260Hを使用)
    ; ---------------------------------------------
    ; 動作モード設定 SMDレジスタ
    ; Mode: 非同期, 8bit, パリティなし, 1ストップビット, x16クロック
    ; 01 00 11 10
    mov dx, SCU_SMD
    mov al, 01001110b
    out dx, al

    ; コマンド設定  SCMレジスタ
    ; Cmd: 送受信イネーブル, エラーリセット, DTR/RTSアクティブ
    ; 00 0 1 0 1 0 1
    mov dx, SCU_SCM
    mov al, 00010101b   ; RTS/DTR ON, RX/TX Enabl
    out dx, al

    ; 割り込みはマスクする  SIMKレジスタ
    mov dx, SCU_SIMK
    mov al, 00000011b
    out dx, al

    ; ---------------------------------------------
    ; 7. メモリ書き込み後に読み出してメモリテストをするループ
    ; ---------------------------------------------
    ; --- Stackless Main Loop ---
    ; CALL も PUSH も使わず、ひたすらベタ書きで回す

    ; ループカウンタ兼アドレスポインタ (SIを使用)
    ; SI = 0000H からスタート
    mov si, 0x0000

main_loop:
    ; --- 書き込み ---
    ; アドレス [DS:SI] にテスト値を書き込む
    mov byte [si], 0x55     ; 書き込む値(01010101)

    ; --- 読み出し ---
    ; アドレス [DS:SI] から値を読み出す
    mov al, byte [si]

    ; --- 比較 ---
    cmp al, 0x55
    jne error_found         ; 一致しない場合はエラー処理へ

    ; 同様に0xAA(10101010)でも確認
    mov byte [si], 0xAA
    mov al, byte [si]
    cmp al, 0xAA
    jne error_found

    ; メモリをクリアして次へ
    mov byte [si], 0x00

next_addr:
    ; --- アドレス更新 ---
    inc si                 ; アドレスをインクリメント
    cmp si, 0000H           ; 0000Hに戻ったかチェック (FFFFHの次は0000H)
    je  segment_update      ; SIが0になったら次のセグメントへ
    jmp main_loop           ; 0でなければループ継続

segment_update:
    ; --- セグメント更新 ---
    mov ax, ds
    add ax, 1000h
    mov ds, ax

    ; --- 終了判定（E0000-FFFFFはROMエリアのため省く）---
    cmp ax, 0e000h
    je all_done

    jmp main_loop

all_done:
    ; --- 終了処理 (全チェック完了) ---
    ; シリアル送信部
    mov dx, SCU_SST
.wait_tx3:
    in al, dx
    test al, 00000001b  ; TX Ready?
    jz .wait_tx3
    
    mov dx, SCU_DATA
    mov al, '#'         ; 終了したことを示す表示
    out dx, al

    ;無限ループで停止
    jmp $

; -------------------------------------------------------------
; エラー処理ルーチン: アドレス(SI)を16進数で出力
; 注意: CALLは使えないため、処理後は NEXT_ADDR へジャンプして戻る
; -------------------------------------------------------------
error_found:
    ; 状態フラグ(BX)を使って、セグメント表示とオフセット表示で
    ; 同じ処理(PRINT_HEX)を使い回す。
    ; レジスタ競合回避のため、DIをフラグとして使用
    ; DI = 1 : セグメント表示中
    ; DI = 0 : オフセット表示中

    mov di, 1   ; 最初はセグメント(DS)を表示
    mov bp, ds  ; 表示用データにDSをセット

print_hex_start:
    mov cx, 4               ; 4桁分ループ (4 nibbles)

print_hex_loop:
    ; 上位4ビットを取り出すために左ローテート
    rol bp, 1
    rol bp, 1
    rol bp, 1
    rol bp, 1
    
    mov ax, bp              ; AXにコピー
    and ax, 000fh           ; 下位4ビットのみ抽出 (0-F)

    ; HEX ASCII変換
    cmp al, 0ah
    jb  is_digit
    add al, 07h             ; 'A'-'F' の場合の調整
is_digit:
    add al, 30h             ; '0' のASCIIコードを足す

    ; --- 文字送信 (SCU) ---
    ; レジスタ退避ができないため、他のレジスタを壊さないよう注意
    ; ここでは AH を作業用、AL を送信データとして使用
    
    mov bl, al              ; 送信文字をBLに一時退避

    ; シリアル送信部
    mov dx, SCU_SST
.wait_tx:
    in al, dx
    test al, 00000001b  ; TX Ready?
    jz .wait_tx
    
    mov dx, SCU_DATA
    mov al, bl
    out dx, al

    loop print_hex_loop     ; CXを減らしてループ

    ; --- アドレス表示完了後の処理 ---
    ; 読みやすくするためアドレスの後にスペースを送る
    ; シリアル送信部
    mov dx, SCU_SST
.wait_tx2:
    in al, dx
    test al, 00000001b  ; TX Ready?
    jz .wait_tx2
    
    mov dx, SCU_DATA
    mov al, ' '
    out dx, al

    ; --- フェーズ切り替え判定 ---
    cmp di, 0               ; 今回の表示はオフセット表示かを確認する
    je error_done           ; BX=0ならオフセット表示完了なので戻る

    ; 現在のSI (エラーアドレス) を保持して表示処理を行う
    ; 16bitアドレスなので4桁のHEXを表示する
    mov di, 0               ; フラグを「オフセット表示」に変更
    mov bp, si              ; 表示する値をSI(オフセット)に変更
    jmp print_hex_start     ; 表示ルーチンへ戻る

error_done:
    ; --- テスト継続 ---
    jmp next_addr

; -----------------------------------------------------------------
; Padding (空白埋め)
; コードの終わりから、リセットベクタの手前までを0xFFで埋める
; -----------------------------------------------------------------
    times ROM_TOTAL - 16 - ($ - $$) db 0xFF

; -----------------------------------------------------------------
; Reset Vector (Physical Address FFFF0h)
; CPUは電源ON時、ここ(ROMの末尾16バイト地点)を実行する
; -----------------------------------------------------------------
reset_vector:
    ; ROMの先頭(start)へジャンプする
    ; 1MBit ROMの場合、物理アドレスは E0000h～FFFFFh にマップされる想定
    ; なので、セグメント E000h, オフセット 0000h へ飛べばよい
    
    jmp 0xE000:0000   ; Far Jump to start of 128KB ROM

    ; ファイルサイズがぴったりROMサイズになるよう調整
    times 16 - ($ - reset_vector) db 0xFF