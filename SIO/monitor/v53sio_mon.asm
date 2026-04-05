; =================================================================
; V53 ROM Monitor for DVE-554 v0.1 2026-04-05
; Target: DVE-554 SIO VME Board
; =================================================================

[BITS 16]
[ORG 0x8000]

; --- ビルド方法 ---
; nasm -f bin v53sio_mon.asm -o v53sio_mon.bin -l v53sio_mon.lst
; -----------------

; ▼▼▼ ROMサイズ設定 (ここを環境に合わせる) ▼▼▼
;%define ROM_SIZE_1024  0x20000  ; 27C010 (128KB)
; 使用するROMサイズを選択
;%define ROM_TOTAL     ROM_SIZE_1024
%define ROM_SIZE_32K  0x8000
; 使用するROMサイズを選択
%define ROM_TOTAL     ROM_SIZE_32K
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
%define WCY4    0x0FFF6 ; プログラマブル・ウェイト・サイクル数設定レジスタ4
%define WCY3    0x0FFF5 ; プログラマブル・ウェイト・サイクル数設定レジスタ3
%define WCY2    0x0FFF4 ; プログラマブル・ウェイト・サイクル数設定レジスタ2
%define WMB1    0x0FFF3 ; プログラマブル・ウェイト・メモリ領域設定レジスタ1
%define RFC     0x0FFF2 ; リフレッシュ・コントロール・レジスタ
%define SBCR    0x0FFF1 ; 
%define TCKS    0x0FFF0 ; 
%define WAC     0x0FFED ; プログラマブル・ウェイト・メモリ・アドレス・コントロール・レジスタ
%define WCY0    0x0FFEC ; プログラマブル・ウェイト・サイクル数設定レジスタ0
%define WCY1    0x0FFEB ; プログラマブル・ウェイト・サイクル数設定レジスタ1
%define WMB0    0x0FFEA ; プログラマブル・ウェイト・メモリ領域設定レジスタ0
%define BRC     0x0FFE9 ; ボー・レート・カウンタ
%define BADR    0x0FFE1 ; 
%define BSEL    0x0FFE0 ; 
%define XAM     0x0FF80 ; 
%define PGR     0x0FF00 ; 

; --- RAM上の変数マップ (ES=0x0000 を前提に使用) ---
; 0x0000-0x03FF は割り込みベクタ(IVT)なので避ける
%define VAR_DUMP_SEG    0x0400  ; Dump: セグメント保存用
%define VAR_DUMP_OFF    0x0402  ; Dump: オフセット保存用
%define VAR_LOAD_SEG    0x0404  ; Load: ターゲットセグメント

%define MPSC1_CTRL 0x00A2
%define MPSC1_DATA 0x00A0
%define MPSC2_CTRL 0x00AA
%define MPSC2_DATA 0x00A8

start:
    cli                     ; 割り込み禁止
    cld                     ; 文字列処理を前方へ
    mov     sp, 0x7FFF      ; SP = 0x7FFF 初期化
    mov     ax, 0x0000
    mov     ds, ax          ; DS = 0000h
    mov     es, ax          ; ES = 0000h
    mov     ss, ax          ; SS = 0000h

    ; --- 2. V53 システムレジスタ初期化 ---
    call v53_sysreg_init

    ; --- 3. TCU (タイマーユニット) 初期化  ---
    call v53_tcu_init

    ; --- 4. 物理IOの初期化（詳細不明） ---
    call dve554_io_init

    ; --- 5. MPSC の初期化 ---
    call mpsc_init            ; 外部MPSC uPD72001のセットアップ

    ; 変数初期化 (RAMエリアをクリア)
    mov word [es:VAR_DUMP_SEG], 0x0000
    mov word [es:VAR_DUMP_OFF], 0x0000
    mov word [es:VAR_LOAD_SEG], 0x2000

    ; スタートメッセージの表示
    mov si, msg_boot
    call puts

; =================================================================
; Main Loop
; =================================================================
monitor_loop:
    mov al, '>'
    call putc
    mov al, ' '
    call putc

    call getc_echo  ; コマンド受信（エコーあり）
    mov bl, al
    
    cmp bl, 'd'     ; dump command
    je do_dump
    cmp bl, 'D'
    je do_dump
    
    cmp bl, 'l'     ; load command
    je do_load
    cmp bl, 'L'
    je do_load
    
    cmp bl, 'g'     ; go command
    je do_go
    cmp bl, 'G'
    je do_go

    ; 知らないコマンドなら改行して戻る
    call putc_crlf
    jmp monitor_loop

; =================================================================
; Command: Dump Memory
; Usage:
;   D               -> Dump next 64 bytes
;   D <Seg> <Off>   -> Set address and dump (e.g., D 0000 8000)
; =================================================================
do_dump:
    call getc_echo      ; 区切り文字受信 (Space or Enter)
    cmp al, 0x0D        ; Enterならすぐ実行
    je .dump_run
    cmp al, ' '         ; Spaceなら引数解析
    je .parse_args
    
    ; それ以外なら無視して実行へ（またはエラー処理）
    call putc_crlf
    jmp .dump_run_start

.parse_args:
    call get_hex_word
    mov [es:VAR_DUMP_SEG], ax
    call skip_space
    call get_hex_word
    mov [es:VAR_DUMP_OFF], ax
    ; ここでEnter待ちをするか、そのまま実行するか
    ; 今回はパラメータ入力後にEnterを押したと仮定して改行
    
.dump_run:
    call putc_crlf              ; 実行直前に改行

.dump_run_start:
    mov cx, 4                   ; 4行表示する
    
.line_loop:
    push cx
    
    mov ax, [es:VAR_DUMP_SEG]   ; セグメントの表示
    call print_hex_word
    mov al, ':'                 ; 区切り文字の:を表示
    call putc
    mov ax, [es:VAR_DUMP_OFF]   ; オフセットの表示
    call print_hex_word
    mov al, ' '                 ; 区切り文字のスペースを表示
    call putc
    
    push ds
    mov ds, [es:VAR_DUMP_SEG]
    mov si, [es:VAR_DUMP_OFF]
    
    mov cx, 16                  ; 16回繰り返すカウンタ
.hex_loop:
    mov al, [si]
    call print_hex_byte         ; メモリ内容の表示
    mov al, ' '                 ; 区切り文字のスペースを表示
    call putc
    inc si                      ; 次のアドレスにする
    loop .hex_loop              ; 16回繰り返し
    
    mov [es:VAR_DUMP_OFF], si   ; オフセットを更新
    
    pop ds
    call putc_crlf              ; 改行する
    pop cx
    loop .line_loop             ; 4回繰り返す
    
    jmp monitor_loop            ; モニタのメインルーチンに飛ぶ

; =================================================================
; Command: Load Intel HEX
; Usage:
;   L           -> Load to default segment (load_seg)
;   L <Seg>     -> Set segment and Load (e.g., L 2000)
; =================================================================
do_load:
    ; 一時的に ES をロード先にするため、デフォルト値をAXへ退避
    mov ax, [es:VAR_LOAD_SEG]
    push es             ; RAM用ESを保存
    push ax             ; デフォルトセグメントを保存
    
    call getc_echo
    cmp al, ' '         ; スペースがあればパラメタ付きと判断
    je .parse_seg
    jmp .start_load

.parse_seg:
    pop ax              ; 不要になったデフォルトを捨てる
    call get_hex_word   ; 新しいセグメント取得
    push ax             ; 保存

.start_load:
    call putc_crlf      ; メッセージ表示前に改行
    mov si, msg_load    ; ロード開始メッセージを表示
    call puts
    
    pop ax
    mov es, ax          ; ロード先をESに設定
    
    ; ターゲット表示
    call print_hex_word ; ESの値を表示
    mov al, ':'         ; 区切り文字を表示
    call putc
    mov al, '0'         ; 本来は0000だが、0と簡易表示
    call putc
    call putc_crlf

.wait_record:
    call getc           ; 開始文字を待つ
    cmp al, ':'
    jne .wait_record

    call get_hex_byte   ; データ長を読み込み
    mov cl, al          ; データ長をcxレジスタに設定
    mov ch, 0
    
    call get_hex_byte   ; 上位アドレスを読み込み
    mov bh, al
    call get_hex_byte   ; 下位アドレスを読み込み
    mov bl, al
    
    call get_hex_byte   ; レコードタイプを読み込み
    cmp al, 01          ; End of File?
    je .handle_eof      ; EOFの処理へ
    cmp al, 00          ; Data Record?
    jne .skip_line      ; その他はスキップ
    
    jcxz .read_chk      ; データ長がゼロならチェックサム読み込み処理
    
.data_loop:
    call get_hex_byte   ; 1バイト読み取り
    mov [es:bx], al     ; ターゲット(ES)へ書き込み
    inc bx              ; 次のアドレスにする
    ; --- 追加: 64KBの境界チェック ---
    jnz .loop_next      ; bxが0にならなければそのまま
    mov ax, es          ; bxが0(一周)したら
    add ax, 0x1000      ; セグメントを64KB分(0x1000)進める
    mov es, ax
    ; -----------------------------

.loop_next:
    loop .data_loop     ; データ長分繰り返す
    
.read_chk:
    call get_hex_byte   ; チェックサム読み取り（読み飛ばし）
    mov al, '.'         ; 1行読んだことを示す"."を出力
    call putc
    jmp .wait_record    ; 次のレコード読み取りへ

.handle_eof:            ; EOFの場合
    call get_hex_byte   ; チェックサムを読み飛ばす
    jmp .finish         ; 読み込み終了処理へ

.skip_line:
    jmp .wait_record    ; 次のレコード読み込みへ

.finish:
    pop es              ; RAM用ESを復帰
    call putc_crlf
    mov si, msg_ok      ; "OK"を表示
    call puts
    jmp monitor_loop    ; モニタのメインルーチンに飛ぶ

; =================================================================
; Command: Go (Execute)
; Format: G <Segment> <Offset>
; Example: G 1000 0000
; =================================================================
do_go:
    ; Gコマンドは入力後に改行
    
    call getc_echo      ; Space?
    cmp al, ' '
    jne .go_default     ; 引数なしならリターン(またはエラー)
    
    ; 1. セグメント (SSSS) を取得
    call get_hex_word   ; AX = Segment
    push ax             ; スタックに積む (あとでRETFでCSになる)
    mov bx, ax          ; DS/ES用のために保存しておく
    
    ; スペース読み飛ばし (もしあれば)
    call skip_space
    
    ; 2. オフセット (OOOO) を取得
    call get_hex_word   ; AX = Offset
    push ax             ; スタックに積む (あとでRETFでIPになる)
    
    call putc_crlf      ; 実行前に改行
    mov si, msg_go
    call puts
    call putc_crlf
    
    ; 3. 実行環境のセットアップ
    ; ジャンプ先のプログラムのために、DS, ES もセグメントに合わせておくのが親切
    mov ds, bx
    mov es, bx

    ; 必要なら割り込み禁止 (OSが自分でセットアップするまで黙らせる)
    cli

    ; 4. ジャンプ！ (Far Return)
    ; スタック上の [IP, CS] をポップして、そこへ飛ぶ
    retf                ; Jump!

.go_default:
    call putc_crlf      ; 改行して
    jmp monitor_loop    ; モニタのメインルーチンに飛ぶ

; =================================================================
; Utilities
; =================================================================

; 文字列出力
puts:
    mov al, [cs:si]
    or al, al
    jz .ret
    call putc
    inc si
    jmp puts
.ret: ret

; 1文字出力
putc:
    push dx
    push ax
    mov dx, MPSC1_CTRL
.wait_tx:
    in al, dx
    test al, 0x04   ; D2: Tx Buffer Empty?
    jz .wait_tx
    mov dx, MPSC1_DATA
    pop ax
    out dx, al
    pop dx
    ret

; 1文字入力
getc:
    push dx
    mov dx, MPSC1_CTRL
.wait_rx:
    in al, dx
    test al, 0x01   ; D0: RX Ready?
    jz .wait_rx
    mov dx, MPSC1_DATA
    in al, dx
    pop dx
    ret

; 1文字入力　エコーバックあり
getc_echo:
    call getc
    push ax
    call putc
    pop ax
    ret

; 改行出力
putc_crlf:
    mov al, 0x0D
    call putc
    mov al, 0x0A
    jmp putc

; -----------------------------------------------------------------
; Helper: 1ワードを4文字のHEXで表示 (例: 0x2F3F -> "2", "F", "3", "F")
; Input: AX
; -----------------------------------------------------------------
print_hex_word:
    push ax
    mov al, ah
    call print_hex_byte
    pop ax

; -----------------------------------------------------------------
; Helper: 1バイトを2文字のHEXで表示 (例: 0x3F -> "3", "F")
; Input: AL
; -----------------------------------------------------------------
print_hex_byte:
    push ax
    push cx

    ; 上位バイトの表示
    push ax
    shr al, 4
    call .digit

    ; 下位バイトの表示
    pop ax
    and al, 0x0F
    call .digit

    pop cx
    pop ax
    ret

; 数値を16進数文字に変換して表示 (0-15 -> 0-9, A-F)
.digit:
    add al, '0'
    cmp al, '9'
    jbe .p
    add al, 7
.p: call putc
    ret

; -----------------------------------------------------------------
; Helper: 4文字のHEXを受信して1ワード(16bit)の数値にする
; Input:  Serial (例: "1", "0", "0", "0")
; Output: AX = 0x1000
; -----------------------------------------------------------------
get_hex_word:
    push bx
    call get_hex_byte_echo
    mov bh, al
    call get_hex_byte_echo
    mov bl, al
    mov ax, bx
    pop bx
    ret

; 16進数2桁入力　エコーバック有り
get_hex_byte_echo:
    push bx
    call getc_echo
    call hex_char_to_bin
    shl al, 4
    mov bl, al
    call getc_echo
    call hex_char_to_bin
    or al, bl
    pop bx
    ret

; -----------------------------------------------------------------
; Helper: 2文字のHEXを受信して1バイトの数値にする
; Input:  Serial (例: "3", "F")
; Output: AL = 0x3F
; -----------------------------------------------------------------
get_hex_byte:
    push bx             ; BH/BLを使うので退避（メインでアドレス用に使ってるため重要）

    ; 上位4bit
    call getc
    call hex_char_to_bin
    shl al, 4
    mov bl, al          ; 一時保存
    
    ; 下位4bit
    call getc
    call hex_char_to_bin
    or al, bl           ; 上位を合成して結果はALへ
    pop bx
    ret

; -----------------------------------------------------------------
; Helper: ASCII文字を数値へ (0-9, A-F -> 0-15)
; Input: AL (ASCII)
; Output: AL (Binary)
; -----------------------------------------------------------------
hex_char_to_bin:
    sub al, '0'
    cmp al, 9
    jbe .done
    sub al, 7           ; 'A'-'F'対応
    and al, 0x0F        ; 小文字対応も含めてざっくりマスク
.done:
    ret

; -----------------------------------------------------------------
; Helper: スペースなどを読み飛ばす
; -----------------------------------------------------------------
skip_space:
    call getc_echo
    ret

; --------------------------------------------------
;  V53 システムレジスタ初期化
; --------------------------------------------------
v53_sysreg_init:
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
; TCU (タイマーユニット) 初期化
; --------------------------------------------------
v53_tcu_init:
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
; 物理IOの初期化
; ---------------------------------------------------
dve554_io_init:
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
mpsc_init:
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
; V53システムレジスタ設定テーブル
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
; TCU タイマー設定テーブル
; --------------------------------------------------
ALIGN 2
TABLE_TCU_REG:
    ; Port1, Val1, Port2, Val2(16)
    db 0xD6, 0x00, 0x36, 0xD0, 0x00, 0x20, 0x4E ; T0設定
    db 0xD6, 0x00, 0x70, 0xD2, 0x00, 0x05, 0x0D ; T0最大値A
    db 0xD6, 0x00, 0xB0, 0xD4, 0x00, 0x05, 0x0D ; T0最大値B
    db 0xFF, 0xFF           ; 終端マーカー

; =================================================================
; Data
; =================================================================
msg_boot: db 0x0D,0x0A,"**  V53 ROM MONITOR for DVE-554 v0.1 2026-04-05  **",0x0D,0x0A,0
msg_load: db "Load HEX...",0
msg_ok:   db "OK",0
msg_go:   db "Go!",0

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
    ; ROMの開始アドレスへジャンプする
    ; 1MBit ROMの場合、物理アドレスは E0000h～FFFFFh にマップされるが、
    ; オリジナルのROMではF000:8100にジャンプしている。
    
    cli
    cld
    jmp 0xF000:0x8000   ; Far Jump to start of 128KB ROM

    ; ファイルサイズがぴったりROMサイズになるよう調整
    times 16 - ($ - reset_vector) db 0xFF