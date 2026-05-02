; =================================================================
; V53 RAM Monitor for DVE-554 v0.3 2026-05-02
; Target: DVE-554 SIO VME Board
; =================================================================

; --- ビルド方法 ---
; Real:   nasm -f bin v53sio_ram_mon.asm -o v53sio_ram_mon.bin -l v53sio_ram_mon.lst
; objcopy -I binary -O ihex --change-addresses=0x0000 v53sio_ram_mon.bin v53sio_ram_mon.hex
; -----------------

; 接続:
;   MPSC#1 INT(Lアクティブ) --[74LS04]--> V53 INTP4 (Hアクティブ)
;   MPSC#2 INT(Lアクティブ) --[74LS04]--> V53 INTP5 (Hアクティブ)
;   MPSC#1 INTAK ----------> V53 INTAK (共通)
;   MPSC#2 INTAK ----------> V53 INTAK (共通)
;
; IOアドレス:
;   MPSC#1 Ch.A CTRL 0x00A2  DATA 0x00A0
;   MPSC#1 Ch.B CTRL 0x00A6  DATA 0x00A4
;   MPSC#2 Ch.A CTRL 0x00AA  DATA 0x00A8
;   MPSC#2 Ch.B CTRL 0x00AE  DATA 0x00AC
;   V53 ICU     REG0 0x00C0  REG1 0x00C2
;
; 割り込みベクタ:
;   ICU Vector base = 0x20
;     TCU TOUT0(INTP0) → INT 0x20 
;   MPSC#1 Vector base = 0x28
;   MPSC#2 Vector base = 0x30

    org 0
    cpu 186

    ; V53 ICU (00C0Hに配置)
    %define ICU_REG0    0x000C0
    %define ICU_REG1    0x000C2

    ; V53 TCU (00D0Hに配置)
    %define TM0_CNT     0x000D0 ; Timer 0 Counter
    %define TM1_CNT     0x000D2 ; Timer 1 Counter
    %define TM2_CNT     0x000D4 ; Timer 2 Counter
    %define TM_CTL      0x000D6 ; Timer Control

    ; V53 DMAU (00E0Hに配置)
    ; DMAUはモニタでは使用しないため、レジスタ定義は省略します。

    ; V53 SCU (00F0Hに配置）
    ; SCUはモニタでは使用しないため、レジスタ定義は省略します。

    ; uPD72001 MPSC #1
    %define MPSC1_A_DATA 0x00A0 ; MPSC #1 Channel A Data Register
    %define MPSC1_A_CTRL 0x00A2 ; MPSC #1 Channel A Control Register
    %define MPSC1_B_DATA 0x00A4 ; MPSC #1 Channel B Data Register
    %define MPSC1_B_CTRL 0x00A6 ; MPSC #1 Channel B Control Register

    ; uPD72001 MPSC #2
    %define MPSC2_A_DATA 0x00A8 ; MPSC #2 Channel A Data Register
    %define MPSC2_A_CTRL 0x00AA ; MPSC #2 Channel A Control Register
    %define MPSC2_B_DATA 0x00AC ; MPSC #2 Channel B Data Register
    %define MPSC2_B_CTRL 0x00AE ; MPSC #2 Channel B Control Register

    %define TX_READY   0x04
    %define RX_READY   0x01

    %define RX_BUF_SIZE 64

section .text

start:
    cli             ; 初期化中は割り込み禁止
    cld             ; 文字列操作で方向フラグをクリアしておく

    ; ---------------------------------------------
    ; 1. セグメントレジスタ初期化
    ; ---------------------------------------------
    push cs     ; CS -> DS
    pop ds
    push cs     ; CS -> ES
    pop es
    mov ax, cs  ; CS -> SS
    mov ss, ax
    mov sp, 0x7FFF
    ; ------------------------------

    call v53_sysreg_init    ; 2. V53 システムレジスタ初期化
    call v53_tcu_init       ; 3. V53 TCU初期化
    call v53_icu_init       ; 4. V53 ICU初期化
    call dve554_io_init     ; 5. 物理IOの初期化（詳細不明）
    call int_vector_init    ; 6. 割り込みベクタの初期化
    call mpsc_init          ; 7. MPSC初期化

    sti

    ; 変数初期化 (RAMエリアをクリア)
    mov word [dump_seg], 0x0000
    mov word [dump_off], 0x0000
    mov word [load_seg], 0x2000
    mov word [head_ptr], 0x0000
    mov word [intsys_flag], 0x0000

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

    cmp bl, 'w'     ; Write command
    je do_write
    cmp bl, 'W'
    je do_write

    cmp al, 'i'     ; Input Port command
    je do_in
    cmp al, 'I'
    je do_in

    cmp al, 'o'     ; Output Port command
    je do_out
    cmp al, 'O'
    je do_out

    cmp al, 's'     ; Scan I/O command
    je do_scan
    cmp al, 'S'
    je do_scan

    cmp al, 't'     ; Scan Timer wait command
    je do_timer
    cmp al, 'T'
    je do_timer

    cmp al, '?'     ; Help
    je cmd_help

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
    mov [dump_seg], ax
    call skip_space
    call get_hex_word
    mov [dump_off], ax
    ; ここでEnter待ちをするか、そのまま実行するか
    ; 今回はパラメータ入力後にEnterを押したと仮定して改行
    
.dump_run:
    call putc_crlf              ; 実行直前に改行

.dump_run_start:
    mov cx, 4                   ; 4行表示する
    
.line_loop:
    push cx
    
    mov ax, [dump_seg]          ; セグメントの表示
    call print_hex_word
    mov al, ':'                 ; 区切り文字の:を表示
    call putc
    mov ax, [dump_off]          ; オフセットの表示
    call print_hex_word
    mov al, ' '                 ; 区切り文字のスペースを表示
    call putc

    mov si, [dump_off]          ; DS変更前に、モニタ変数からオフセットをSIにロード

    push ds                     ; モニタのDSを保存
    mov ds, [dump_seg]          ; DSをターゲットセグメントに変更
    
    mov cx, 16                  ; 16回繰り返すカウンタ
.hex_loop:
    mov al, [si]
    call print_hex_byte         ; メモリ内容の表示
    mov al, ' '                 ; 区切り文字のスペースを表示
    call putc
    inc si                      ; 次のアドレスにする
    loop .hex_loop              ; 16回繰り返し    

    pop ds                      ; DSをモニタ用に戻す

    mov [dump_off], si          ; DS復帰後に、SIの値をモニタ変数に保存

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
    mov ax, [load_seg]
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
; Command: Execute
; Usage:
;   G <Seg> <Off>
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

; ==============================================================
; Command: Write Memory
; Usage:
;   W <Seg> <Off> <Val>
; ==============================================================
do_write:    
    call getc_echo      ; Space?
    cmp al, ' '
    jne error           ; 引数なしならリターン(またはエラー)

    ; 1. セグメント (SSSS) を取得
    call get_hex_word   ; AX = Segment
    push ax             ; ターゲットセグメントを保存
    
    call getc_echo      ; Space?
    cmp al, ' '
    jne error           ; 引数なしならリターン(またはエラー)
    
    ; 2. オフセット (OOOO) を取得
    call get_hex_word   ; AX = Offset
    push ax             ; ターゲットオフセットを保存

    call getc_echo      ; Space?
    cmp al, ' '
    jne error           ; 引数なしならリターン(またはエラー)

    ; 3. 設定データ (VV) を取得
    call get_hex_byte_echo   ; AL = Value

    pop bx              ; bx = Offset
    pop dx              ; dx = Target Segment

    ; 次回のDコマンドのためにダンプ位置変数を更新する
    mov [dump_seg], dx
    mov [dump_off], bx
    
    mov ds, dx          ; DS再設定
    mov [ds:bx], al     ; 書き込み！
    
    push cs             ; DSを復帰 (CS=DS前提のモニタなので)
    pop ds

    mov si, msg_done
    call puts
    jmp monitor_loop

; ==============================================================
; Command: Input from Port
; Usage:
;   I <Port>
; ==============================================================
do_in:
    call getc_echo
    cmp al, ' '         ; スペースがあればパラメタ付きと判断
    jne error           ; パラメタが無い場合はエラー処理へ

    call get_hex_word   ; ポートアドレスを取得
    mov dx, ax          ; 保存
    in al, dx           ; I/O Read
    
    push ax
    call putc_crlf      ; メッセージ表示前に改行
    mov si, msg_in_res
    call puts
    pop ax

    call print_hex_byte ; 値を表示

    call putc_crlf      ; 改行して
    jmp monitor_loop    ; モニタのメインルーチンに飛ぶ

; ==============================================================
; Command: Output to Port
; Usage
;   O <Port> <Val>
; ==============================================================
do_out:
    call getc_echo
    cmp al, ' '         ; スペースがあればパラメタ付きと判断
    jne error           ; パラメタが無い場合はエラー処理へ

    call get_hex_word   ; ポートアドレスを取得
    push ax             ; スタックに積む

    call getc_echo
    cmp al, ' '         ; スペースがあれば第2パラメタがあると判断
    jne error_pop       ; 第2パラメタが無い場合はエラー処理へ
    
    call get_hex_byte_echo   ; 出力値を取得
    pop dx              ; スタックからDXにセット
    
    out dx, al          ; I/O Write
    
    call putc_crlf      ; 書き込み完了後、まず改行する
    mov si, msg_done    ; DONEを表示。改行付き。
    call puts
    
    jmp monitor_loop    ; モニタのメインルーチンに飛ぶ

error_pop:
    pop ax              ; 使わなかったスタックを捨てる
    jmp error

; ==============================================================
; Command: Scan I/O Ports
; Usage:
;   S <Start_port> <End_port>
; Description: Reads ports and prints if value is NOT 0xFF
; ==============================================================
do_scan:
    call getc_echo
    cmp al, ' '         ; スペースがあればパラメタ付きと判断
    jne error           ; パラメタが無い場合はエラー処理へ

    call get_hex_word   ; スタートポートアドレスを取得
    mov bx, ax          ; BX = Start Address
    
    call getc_echo
    cmp al, ' '         ; スペースがあれば第2パラメタがあると判断
    jne error_pop       ; 第2パラメタが無い場合はエラー処理へ

    call get_hex_word   ; エンドポートアドレスを取得
    mov cx, ax          ; CX = End Address

    cmp bx, cx          ; 開始 > 終了 ならエラー終了
    ja error

    call putc_crlf
    mov si, msg_scan_start
    call puts

.scan_loop:
    mov dx, bx          ; DXにポートアドレス設定
    in al, dx           ; I/O Read

    cmp al, 0xFF        ; 0xFF (Empty Bus) なら表示しない
    je .next_port

    push ax             ; Readした値をスタックに保存

    ; --- 有効な値が見つかった場合の表示 ---
    ; [Port]: Value
    mov ax, bx
    call print_hex_word ; ポートアドレスの表示
    mov al, ':'
    call putc
    mov al, ' '
    call putc
    
    pop ax
    call print_hex_byte ; Readした値の表示
    
    mov si, msg_space   ; "  "
    call puts

    ; 1行に見やすく並べるため、適当な間隔で改行を入れる等の工夫も可能ですが
    ; ここでは単純にリスト形式で改行します
    call putc_crlf

.next_port:
    inc bx              ; 次のアドレスへ
    
    ; キー入力チェック（長いスキャンを中断できるようにする）
    call getc_noblock   ; 1文字取得関数 (非ブロッキング)
    jc .abort           ; Carry Flag(CF)=1なら何かキーが押されたので中断

    cmp bx, cx
    jbe .scan_loop      ; BX <= CX ならループ

    mov si, msg_done    ; 終了メッセージの表示
    call puts
    jmp monitor_loop

.abort:
    mov si, msg_abort   ; 中断メッセージの表示
    call puts
    jmp monitor_loop

; ==============================================================
; Command: Timer
;   T          -> Show current tick counter (32-bit HEX)
;   T <val>    -> Wait for <val> ticks (10ms unit)
; ==============================================================
do_timer:
    call getc_echo      ; コマンド('T')の次の文字を取得
    cmp al, 0x0D        ; Enterキー(CR)なら表示モードへ
    je .show_counter
    cmp al, ' '         ; スペースならWaitモードへ
    jne error           ; それ以外はエラー

    ; --- Wait Mode (引数あり: T 0064 等) ---
    call get_hex_word   ; AX = 待ち時間 (0x0064 = 1秒)

    ; 開始時刻を保存 (Start Time)
    mov bx, [tick_counter_lo]

.wait_loop:
    ; 1. 現在時刻を取得
    mov cx, [tick_counter_lo]
    
    ; 2. 経過時間を計算 (Current - Start)
    ; オーバーフローしても、この引き算の結果は正しい経過時間になる
    sub cx, bx          
    
    ; 3. 経過時間 < 待ち時間 ならループ継続
    cmp cx, ax
    jb .wait_loop       ; Jump if Below (unsigned compare)

    ; 指定時間経過した
    mov si, msg_done
    call puts
    jmp monitor_loop

.show_counter:
    ; --- Show Counter Mode (引数なし: Tのみ) ---
    call putc_crlf
    
    mov si, msg_tick    ; "Tick: "
    call puts

    ; 32bitカウンタを [High][Low] の順で表示
    mov ax, [tick_counter_hi]
    call print_hex_word
    mov ax, [tick_counter_lo]
    call print_hex_word
    
    call putc_crlf
    jmp monitor_loop

; ==============================================================
; Command: Help
; ==============================================================
cmd_help:
    call putc_crlf
    mov si, msg_help
    call puts
    jmp monitor_loop

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
    mov dx, MPSC1_A_CTRL
.wait_tx:
    in al, dx
    test al, TX_READY   ; D2: Tx Buffer Empty?
    jz .wait_tx
    mov dx, MPSC1_A_DATA
    pop ax
    out dx, al
    pop dx
    ret

; 1文字入力
getc:
    ; 1文字取得関数 (ブロッキング) ---
    call getc_noblock
    jnc getc
    ret

    ; 1文字取得関数 (非ブロッキング 受信割り込み方式) ---
    ; 戻り値: AL=データ, Carry Flag(CF)=1ならデータあり/0なら空
getc_noblock:
    push bx
    mov bx, [tail_ptr]
    cmp bx, [head_ptr]
    je  .empty               ; 等しければデータなし

    mov al, [rx_buffer + bx]
    inc bx
    cmp bx, RX_BUF_SIZE
    jne .next
    xor bx, bx
.next:
    mov [tail_ptr], bx
    stc                     ; CF = 1
    pop bx
    ret
.empty:
    clc                     ; CF = 0
    pop bx
    RET

    ; 1文字取得関数 (ブロッキング ポーリング方式) ---
getc_polling:
    push dx
    mov dx, MPSC1_A_CTRL
.wait_rx:
    in al, dx
    test al, RX_READY   ; D0: RX Ready?
    jz .wait_rx
    mov dx, MPSC1_A_DATA
    in al, dx
    pop dx
    ret

; 1文字入力 エコーバックあり
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

; 16進数2桁入力 エコーバック有り
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

; -----------------------------------------------------------------
; Helper: エラーメッセージ出力後モニタに戻る
; -----------------------------------------------------------------
error:
    mov si, msg_error
    call puts
    jmp monitor_loop

; -----------------------------------------------------------------
; 割り込みベクタの初期化
; -----------------------------------------------------------------
int_vector_init:
    push ds
    push es
    cld

    mov si, TABLE_INT_VECTOR
    xor ax, ax
    mov es, ax          ; es = 0x0000

.set_loop:
    mov al, [si]        ; al = ベクタ番号 をロード
    cmp al, 0xff        ; 終端チェック
    je  .done
    
    inc si              ; ベクタ番号分進める
    mov dx, [si]        ; dx = オフセット退避
    add si, 2           ; オフセット分進める
    
    ; ベクタテーブルのアドレス計算 (VectorNum * 4)
    ; V53では 0x0000:0xxxxx がベクタ領域
    xor bh, bh
    mov bl, al          ; bx = ベクタ番号
    shl bx, 2           ; bx = bx * 4 (1つのベクタは4バイト)

    ; ベクタの書き換え
    mov [es:bx], dx        ; オフセットを書き込み
    mov ax, cs             ; 現在のcsを取得
    mov [es:bx+2], ax      ; セグメントとして書き込み

    jmp  .set_loop       ; 次のベクタへ

.done:
    pop  es
    pop  ds
    ret

    ; 割り込みベクタの初期化テーブル
    ; 設定したいベクタのリスト (ベクタ番号, ハンドラのオフセット)
ALIGN 2
TABLE_INT_VECTOR:
    ; INT 0x00 ～ 0x05
    db 0x00                         
    dw _isr_int0x00      ;INT 0x00: DIV/DIVU Divide Error
    db 0x01
    dw _isr_int0x01      ;INT 0x01: BRK Flag (Simgle Step)
    db 0x02
    dw _isr_int0x02      ;INT 0x02: NMI
    db 0x03
    dw _isr_int0x03      ;INT 0x03: BRK3
    db 0x04
    dw _isr_int0x04      ;INT 0x04: BRKV
    db 0x05
    dw _isr_int0x05      ;INT 0x05: CHKIND境界オーバー
    ; INT 0x20 ～ 0x27
    ; V53 ICUのハンドラ
    db 0x20
    dw _isr_int0x20      ;INT 0x20 ICU INTP0 割り込みハンドラ (タイマー割り込み)
    db 0x21
    dw _isr_int0x21      ;INT 0x21 ICU INTP1 未使用
    db 0x22
    dw _isr_int0x22      ;INT 0x22 ICU INTP2 未使用
    db 0x23
    dw _isr_int0x23      ;INT 0x23 ICU INTP3 未使用：TOUT1に接続された割り込み
    db 0x24
    dw _isr_int0x24      ;INT 0x24 ICU INTP4 未使用
    db 0x25
    dw _isr_int0x25      ;INT 0x25 ICU INTP5 未使用
    db 0x26
    dw _isr_int0x26      ;INT 0x26 ICU INTP6 未使用：TOUT2に接続された割り込み
    db 0x27
    dw _isr_int0x27      ;INT 0x27 ICU INTP7 未使用
    ; INT 0x28 ～ 0x2f
    ; MPSC#1のハンドラ
    db 0x28
    dw _isr_int0x28      ;INT 0x28 MPSC#1 Ch.B 未使用
    db 0x29
    dw _isr_int0x29      ;INT 0x29 MPSC#1 Ch.B 未使用
    db 0x2a
    dw _isr_int0x2a      ;INT 0x2A MPSC#1 Ch.B 未使用
    db 0x2b
    dw _isr_int0x2b      ;INT 0x2B MPSC#1 Ch.B 未使用
    db 0x2c
    dw _isr_int0x2c      ;INT 0x2C MPSC#1 Ch.A 未使用
    db 0x2d
    dw _isr_int0x2d      ;INT 0x2D MPSC#1 Ch.A 未使用
    db 0x2e
    dw _isr_int0x2e      ;INT 0x2E MPSC#1 Ch.A 受信割り込みハンドラ
    db 0x2f
    dw _isr_int0x2f      ;INT 0x2F MPSC#1 Ch.A 未使用
    ; INT 0x30 ～ 0x37        
    ; MPSC#2のハンドラ
    db 0x30
    dw _isr_int0x30      ;INT 0x30 MPSC#2 Ch.B 未使用
    db 0x31
    dw _isr_int0x31      ;INT 0x31 MPSC#2 Ch.B 未使用
    db 0x32
    dw _isr_int0x32      ;INT 0x32 MPSC#2 Ch.B 未使用
    db 0x33
    dw _isr_int0x33      ;INT 0x33 MPSC#2 Ch.B 未使用
    db 0x34
    dw _isr_int0x34      ;INT 0x34 MPSC#2 Ch.A 未使用
    db 0x35
    dw _isr_int0x35      ;INT 0x35 MPSC#2 Ch.A 未使用
    db 0x36
    dw _isr_int0x36      ;INT 0x36 MPSC#2 Ch.A 受信割り込みハンドラ（現在は未使用）
    db 0x37
    dw _isr_int0x37      ;INT 0x37 MPSC#2 Ch.A 未使用
    db 0xff                ; 終端マーカー

; ===================================================
;  Interrupt handler
; ===================================================
; INT 0x00 DIV/DIVU Divide Error
_isr_int0x00:
    cli
    or byte [intsys_flag], 0x01    ; 割り込み発生フラグセット
    sti
    iret

; INT 0x01 BRK Flag (Simgle Step)
_isr_int0x01:
    cli
    or byte [intsys_flag], 0x02    ; 割り込み発生フラグセット
    sti
    iret

; INT 0x02 NMI
_isr_int0x02:
    cli
    or byte [intsys_flag], 0x04    ; 割り込み発生フラグセット
    sti
    iret

; INT 0x03 BRK3
_isr_int0x03:
    cli
    or byte [intsys_flag], 0x08    ; 割り込み発生フラグセット
    sti
    iret

; INT 0x04 BRKV
_isr_int0x04:
    cli
    or byte [intsys_flag], 0x10    ; 割り込み発生フラグセット
    sti
    iret

; INT 0x05 CHKIND境界オーバー
_isr_int0x05:
    cli
    or byte [intsys_flag], 0x20    ; 割り込み発生フラグセット
    sti
    iret

; ---------------------------------------------------------
; INT 0x20 (INTP0) Timer0 (100Hz) 割り込みハンドラ
; ---------------------------------------------------------
_isr_int0x20:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x20_flag]    ; 割り込み発生フラグセット

    ; --- 32bit カウンタのインクリメント ---
    inc word [tick_counter_lo]
    jnz .skip_carry
    inc word [tick_counter_hi]
.skip_carry:
    ; --- EOI (End of Interrupt) 発行 ---
    ; これを送らないと次の割り込みが発生しません
    mov al, 0x20         ; Non-Specific EOI
    mov dx, ICU_REG0
    out dx, al

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; ---------------------------------------------------------
; INT 0x21 (INTP1) ハンドラ - 未使用
; ---------------------------------------------------------
_isr_int0x21:
    cli
    inc word [int0x21_flag]    ; 割り込み発生フラグセット
    sti
    iret

; ---------------------------------------------------------
; INT 0x22 (INTP2) ハンドラ - 未使用
; ---------------------------------------------------------
_isr_int0x22:
    cli
    inc word [int0x22_flag]    ; 割り込み発生フラグセット
    sti
    iret

; ---------------------------------------------------------
; INT 0x23 (INTP3) ハンドラ - 未使用
; ---------------------------------------------------------
_isr_int0x23:
    cli
    inc word [int0x23_flag]    ; 割り込み発生フラグセット
    sti
    iret

; ---------------------------------------------------------
; INT 0x24 (INTP4) ハンドラ - MPSCカスケード割り込み
; ---------------------------------------------------------
_isr_int0x24:
    cli
    inc word [int0x24_flag]    ; 割り込み発生フラグセット
    sti
    iret

; ---------------------------------------------------------
; INT 0x25 (INTP5) ハンドラ - MPSCカスケード割り込み
; ---------------------------------------------------------
_isr_int0x25:
    cli
    inc word [int0x25_flag]    ; 割り込み発生フラグセット
    sti
    iret

; ---------------------------------------------------------
; INT 0x26 (INTP6) ハンドラ - 未使用
; ---------------------------------------------------------
_isr_int0x26:
    cli
    inc word [int0x26_flag]    ; 割り込み発生フラグセット
    sti
    iret

; ---------------------------------------------------------
; INT 0x27 (INTP7) ハンドラ - 未使用
; ---------------------------------------------------------
_isr_int0x27:
    cli
    inc word [int0x27_flag]    ; 割り込み発生フラグセット
    sti
    iret

; --------------------------------------
; Int 0x28
; --------------------------------------
_isr_int0x28:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx
    
    inc word [int0x28_flag]     ;割り込み発生フラグセット

    mov dx, MPSC1_A_CTRL	    ;MPSC #1 コマンドポート 0x00A2 を指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x29
; --------------------------------------
_isr_int0x29:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x29_flag]     ;割り込み発生フラグセット

    mov dx, MPSC1_A_CTRL	    ;MPSC #1 コマンドポート 0x00A2 を指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x2a
; --------------------------------------
_isr_int0x2a:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x2a_flag]     ;割り込み発生フラグセット

    mov dx, MPSC1_A_CTRL	    ;MPSC #1 コマンドポート 0x00A2 を指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x2b
; --------------------------------------
_isr_int0x2b:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x2b_flag]     ;割り込み発生フラグセット

    mov dx, MPSC1_A_CTRL	    ;MPSC #1 コマンドポート 0x00A2 を指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x2c
; --------------------------------------
_isr_int0x2c:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x2c_flag]     ;割り込み発生フラグセット

    mov dx, MPSC1_A_CTRL	    ;MPSC #1 コマンドポート 0x00A2 を指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x2d
; --------------------------------------
_isr_int0x2d:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x2d_flag]     ;割り込み発生フラグセット
    
    mov dx, MPSC1_A_CTRL	    ;MPSC #1 コマンドポート 0x00A2 を指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x2e MPSC#1 Ch.A 受信割り込みハンドラ
; --------------------------------------
_isr_int0x2e:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x2e_flag]     ; 割り込み発生フラグセット

    ; uartデータレジスタから読み込み
    mov dx, MPSC1_A_DATA
    in  al, dx                  ; 1バイト受信

    ; リングバッファへ格納
    mov bx, [head_ptr]          ; バッファポインタをbxに設定
    mov [rx_buffer + bx], al    ; 受信データを格納
    
    inc bx                      ; ポインタを加算
    cmp bx, RX_BUF_SIZE         ; バッファオーバーフローチェック
    jne .skip_wrap
    xor bx, bx                  ; バッファポインタをリセット
.skip_wrap:
    mov [head_ptr], bx          ; バッファポインタを保存
    
    ; MPSC EOI / Error Reset
    mov dx, MPSC1_A_CTRL	    ; MPSC #1 コマンドポート 0x00A2 を指定
    mov al, 0x38
    out dx, al	                ; ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x2f
; --------------------------------------
_isr_int0x2f:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x2f_flag]     ;割り込み発生フラグセット
    
    mov dx, MPSC1_A_CTRL	    ; MPSC #1 コマンドポート 0x00A2 を指定
    mov al, 0x38
    out dx, al	                ; ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x30
; --------------------------------------
_isr_int0x30:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x30_flag]     ;割り込み発生フラグセット

    mov dx, MPSC2_A_CTRL	    ;MPSC #2 コマンドポート 0x00AAを指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x31
; --------------------------------------
_isr_int0x31:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x31_flag]     ;割り込み発生フラグセット

    mov dx, MPSC2_A_CTRL	    ;MPSC #2 コマンドポート 0x00AAを指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x32
; --------------------------------------
_isr_int0x32:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x32_flag]     ;割り込み発生フラグセット

    mov dx, MPSC2_A_CTRL	    ;MPSC #2 コマンドポート 0x00AAを指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x33
; --------------------------------------
_isr_int0x33:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x33_flag]     ;割り込み発生フラグセット

    mov dx, MPSC2_A_CTRL	    ;MPSC #2 コマンドポート 0x00AAを指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x34
; --------------------------------------
_isr_int0x34:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x34_flag]     ;割り込み発生フラグセット

    mov dx, MPSC2_A_CTRL	    ;MPSC #2 コマンドポート 0x00AAを指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x35
; --------------------------------------
_isr_int0x35:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x35_flag]     ;割り込み発生フラグセット
    
    mov dx, MPSC2_A_CTRL	    ;MPSC #2 コマンドポート 0x00AAを指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x36
; --------------------------------------
_isr_int0x36:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x36_flag]     ;割り込み発生フラグセット
    
    mov dx, MPSC2_A_CTRL	    ;MPSC #2 コマンドポート 0x00AAを指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------
; INT 0x37
; --------------------------------------
_isr_int0x37:
    cli	                        ;割り込み禁止
    push ax
    push bx
    push dx

    inc word [int0x37_flag]     ;割り込み発生フラグセット
    
    mov dx, MPSC2_A_CTRL	    ;MPSC #2 コマンドポート 0x00AAを指定
    mov al, 0x38
    out dx, al	                ;ポートへ出力

    pop dx
    pop bx
    pop ax
    sti	                        ;割り込み許可
    iret	                    ;割り込み復帰

; --------------------------------------------------
;  V53 CPUシステムレジスタ初期化
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

; V53システムレジスタ設定テーブル
ALIGN 2
TABLE_V53_REG:
    db 0xFE, 0xFF, 0x00     ; FFFE (SCTL) = 0x00 16bit I/O boundary
    db 0xFD, 0xFF, 0x06     ; FFFD (OPSEL)= 0x06 Enable ICU,TCU  Disable DMAU,SCU
    db 0xFC, 0xFF, 0x00     ; FFFC (OPHA) = 0x00
    db 0xFB, 0xFF, 0xE0     ; FFFB (DULA) = 0xE0 DCU:0x00E0
    db 0xFA, 0xFF, 0xC0     ; FFFA (IULA) = 0xC0 ICU:0x00C0
    db 0xF9, 0xFF, 0xD0     ; FFF9 (TULA) = 0xD0 TCU:0x00D0
    db 0xF8, 0xFF, 0xF0     ; FFF8 (SULA) = 0xF0 SCU:0x00F0
    db 0xEA, 0xFF, 0x00     ; FFEA (WMB0) = 0x00
    db 0xEB, 0xFF, 0x00     ; FFEB (WCY1) = 0x00
    db 0xEC, 0xFF, 0x00     ; FFEC (WCY0) = 0x00
    db 0xF3, 0xFF, 0x73     ; FFF3 (WMB1) = 0x73
    db 0xED, 0xFF, 0x00     ; FFED (WAC)  = 0x00
    db 0xF4, 0xFF, 0x10     ; FFF4 (WCY2) = 0x10
    db 0xF5, 0xFF, 0x22     ; FFF5 (WCY3) = 0x22
    db 0xF6, 0xFF, 0x10     ; FFF6 (WCY4) = 0x10
    db 0xF2, 0xFF, 0x00     ; FFF2 (RFC)  = 0x00
    db 0xE9, 0xFF, 0x00     ; FFE9 (BRC)  = 0x00
    db 0xF0, 0xFF, 0x02     ; FFF0 (TCKS) = 0x02
    db 0xF1, 0xFF, 0x00     ; FFF1 (SBCR) = 0x00
    db 0xFF, 0xFF, 0xFF     ; 終端マーカー

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

; TCU タイマー設定テーブル
ALIGN 2
TABLE_TCU_REG:
    ; Port1, Val1, Port2, Val2(16)
    dw TM_CTL  ; T0設定
    db 0x36
    dw TM0_CNT
    dw 0x4E20

    dw TM_CTL  ; T0最大値A
    db 0x70
    dw TM1_CNT
    dw 0x0D05

    dw TM_CTL  ; T0最大値B
    db 0xB0
    dw TM2_CNT
    dw 0x0D05
        
    dw 0x0FFFF ; 終端マーカー

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

; ---------------------------------------
; V53 ICUの初期化
; ---------------------------------------
v53_icu_init:
    MOV SI, TABLE_V53_ICU	;I/O設定テーブルの先頭を指定
.loop:
    MOV DX, CS:[SI]	        ;テーブルからポート番号(Word)をロード
    CMP DX, 0x0FFFF	        ;終端マーカー（0xFFFF）かチェック
    JZ .done	            ;終端なら終了（RETへ）
    mov al, cs:[si+02]	    ;設定値(byte)をロード
    out dx, al	            ;ポートへ出力
    add si, 3	            ;次のエントリ（3バイト後）へ
    jmp .loop	            ;ループ
.done:
    ret

ALIGN 2
TABLE_V53_ICU:
    dw ICU_REG0
    db 0x11    ; IIW1: 00010001b (Edge Trigger, カスケード拡張モード, IIW4有効)
    dw ICU_REG1  
    db 0x20    ; IIW2: 00100000b (Vector Offset = 0x20 (INT 32))
    dw ICU_REG1
    db 0x30    ; IIW3: 00110000b (INTP4, INTP5はスレーブ接続)
    dw ICU_REG1
    db 0x03    ; IIW4: 00000011b (通常ネストモード、通常FIモード、8086モード)
    dw ICU_REG1
    db 0xCE    ; IMKW: 11001110b (INTP4, INTP5, INTP0以外はマスクする)     
    dw 0x0FFFF

; =============================================================
; uPD72001 (MPSC) 初期化シーケンス
; CPU: 8086
; 対象: MPSC #1 / MPSC #2  チャンネルAのみを使用
;
; 設定内容:
;   非同期モード, 9600bps (BRGカウント=0x001E, CLK=x16),
;   8データビット, ストップビット1, パリティなし
;   全受信文字割り込み有効
;   割り込みベクタベース = MPSC #1 0x28, MPSC #2 0x29
; =============================================================
 
; =============================================================
; mpsc_init  - MPSCメイン初期化ルーチン
; 入力: なし / 破壊: AX, BX, CX, DX
; =============================================================
mpsc_init:
    ; =========================================================
    ; Phase 1: ポインタリセット → チャンネルリセット
    ; CR0 ポインタを確実に0にしてからChannel Resetを発行する
    ; =========================================================
 
    ; --- MPSC#1 チャンネルA ---
    mov dx, MPSC1_A_CTRL
    mov al, 0x00
    out dx, al              ; CR0選択（ポインタリセット）
    out dx, al              ; CR0選択（ポインタリセット）
    mov al, 0x18             ; Channel Reset コマンド
    out dx, al
 
    ; --- MPSC#2 チャンネルA ---
    mov dx, MPSC2_A_CTRL
    mov al, 0x00
    out dx, al              ; CR0選択（ポインタリセット）
    out dx, al              ; CR0選択（ポインタリセット）
    mov al, 0x18
    out dx, al
  
    ; リセット後安定待ち（約100ループ）
    mov cx, 100
.wait_reset:
    nop
    nop
    nop
    loop .wait_reset

    ; =========================================================
    ; Phase 2: CR1 - 割り込み/DMA設定
    ; CR1 = 0x10: D4-D3=10(全受信文字で割り込み),
    ;            D1=0(送信割り込み禁止), D0=0(外部割り込み禁止)
    ; =========================================================
    mov dx, MPSC1_A_CTRL
    mov al, 1
    out dx, al              ; CR1
    mov al, 0x10             ; 受信割り込み可能
    out dx, al
    mov dx, MPSC2_A_CTRL
    mov al, 1
    out dx, al              ; CR1
    mov al, 0x10             ; 受信割り込み可能
    out dx, al

    ; =========================================================
    ; Phase 3: CR2A - 割り込み/DMA設定
    ; CR2 = 0x30 
    ;  D5=1: ベクタモード
    ;  D4-D3=10: 86応答モード
    ;  D1-D0=00: 両チャンネルとも割り込み
    ;  D2=0: A/BチャネルのPriority Select
    ; =========================================================
    mov al, 2
    mov bl, 0x0e0    ; 0000 0000b
    call mpsc_write_both

    ; =========================================================
    ; Phase 4: CR4 - 送受信共通フォーマット設定
    ; 非同期モード, x16クロック, ストップビット1, パリティなし
    ; CR4 = 0x44: D7-D6=00(パリティなし), D5-D4=01(1stop),
    ;             D3-D2=00(Async), D1-D0=01(x16)
    ; ※ CR4はCR3/CR5より先に設定すること
    ; =========================================================
    mov al, 4
    mov bl, 0x44
    call mpsc_write_both  ; Aチャンネル両方に書き込み
 
    ; =========================================================
    ; Phase 5: CR12/CR13 - BRGタイムコンスタント設定
    ; ボーレート9600bps, CLKソース, x16分周の場合:
    ;   カウント値 = 0x001E (30)
    ; CR12: タイムコンスタント下位8ビットと上位8ビットを送受信別に書き込む
    ; =========================================================
 
    ; --- MPSC#1 チャンネルA ---
    mov dx, MPSC1_A_CTRL
    mov al, 12          ; CR12選択
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
 
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 2           ; 送信BRGレジスタセットモード有効
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al

    ; --- MPSC#2 チャンネルA ---
    mov dx, MPSC2_A_CTRL
    mov al, 12          ; CR12選択
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al

    mov al, 12          ; Select CR12
    out dx, al
    mov al, 2           ; 送信BRGレジスタセットモード有効
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
 
    ; =========================================================
    ; Phase 6: CR15 - クロックソースとピン機能選択
    ; CR15 = 0x56: DPLL入力はBRG, RTSCとTTLCはBRG出力
    ; =========================================================
    mov al, 15
    mov bl, 0x56
    call mpsc_write_both
 
    ; =========================================================
    ; Phase 7: CR14 - BRG動作許可
    ; CR14 = 0x07: BRGソース=システムCLK, 送受信BRGカウント有効
    ; D2=1(BR CLK=SYS CLK), D1=1(送信BRG有効), D0=1(受信BRG有効)
    ; =========================================================
    mov al, 14
    mov bl, 0x07
    call mpsc_write_both

    ; =========================================================
    ; Phase 8: CR11 - 外部ステータス割り込み要因設定
    ; CR11 = 0h : すべての拡張E/S割り込み要因を完全に禁止する
    ; =========================================================
    mov al, 11
    mov bl, 0x00
    call mpsc_write_both

    ; =========================================================
    ; Phase 9: CR3 - 受信設定・イネーブル
    ; CR3 = 0xC1: D7-D6=11(8ビット受信), D0=1(受信イネーブル)
    ; =========================================================
    mov al, 3
    mov bl, 0xC1
    call mpsc_write_both
 
    ; =========================================================
    ; Phase 10: CR5 - 送信設定・イネーブル
    ; CR5 = 0xEA: D7=1(DTRアサート), D6-D5=11(8ビット送信),
    ;            D3=1(送信イネーブル), D1=1(RTSアサート)
    ; DTR/RTSを初期からアサートしない場合は 0x68 を使用:
    ;   CR5 = 0x68: D6-D5=11(8ビット), D3=1(TX EN), DTR/RTS=0
    ; =========================================================
    mov al, 5
    mov bl, 0xEA
    call mpsc_write_both

    ; =========================================================
    ; Phase 11: CR0  - 内部のCRC計算回路を初期化するコマンドを発行（ASYNCでは不要）
    ; =========================================================
    ;mov dx, MPSC1_A_CTRL
    ;mov al, 0x80       ;送信CRC計算回路の初期化 (Initialize Tx CRC Calculator)
    ;out dx, al    
    ;mov al, 0x40       ;受信CRC計算回路の初期化 (Initialize Rx CRC Calculator)
    ;out dx, al
 
    ;mov dx, MPSC2_A_CTRL
    ;mov al, 0x80
    ;out dx, al
    ;mov al, 0x40
    ;out dx, al

    ; =========================================================
    ; Phase 12: チャンネルＢの設定
    ; =========================================================
    mov dx, MPSC1_B_CTRL
    mov al, 0x00            ; ポインタリセット
    out dx, al
    out dx, al

    mov dx, MPSC2_B_CTRL
    mov al, 0x00            ; ポインタリセット
    out dx, al
    out dx, al
        
    mov al, 0x18            ; Channel Reset コマンド
    mov dx, MPSC1_B_CTRL
    out dx, al
    mov dx, MPSC2_B_CTRL
    out dx, al

    mov cx, 100
.wait_loop:
    nop
    nop
    nop
    loop .wait_loop

    ; =========================================================
    ; Phase 13: CR2B - 割り込みベクタ設定（チャンネルBで設定必要）
    ; ベクタベース = MPSC #1 0x28, MPSC #2 0x30
    ; =========================================================
    mov al, 2             ; CR2Bの設定
    mov dx, MPSC1_B_CTRL
    out dx, al
    mov dx, MPSC2_B_CTRL
    out dx, al
        
    mov al, 0x28             ; MPSC#1のベクタ設定
    mov dx, MPSC1_B_CTRL
    out dx, al
        
    mov al, 0x30             ; MPSC#2のベクタ設定
    mov dx, MPSC2_B_CTRL
    out dx, al

    ; =========================================================
    ; Phase 14: CR1B - 割り込み/DMA設定
    ; CR1B = 0x00: D4-D3=0(受信割り込み完全禁止)
    ;             D2=0(固定ベクタ)
    ;             D1=0(送信割り込み禁止), D0=0(外部割り込み禁止)
    ; =========================================================
    mov al, 1             ; CR1Bの設定
    mov dx, MPSC1_B_CTRL
    out dx, al
    mov dx, MPSC2_B_CTRL
    out dx, al
   
    mov al, 0x00             ; ベクタ修飾無効、Bチャネル全割り込み禁止
    mov dx, MPSC1_B_CTRL
    out dx, al
    mov dx, MPSC2_B_CTRL
    out dx, al
 
    ; =========================================================
    ; Phase 15: CR11B - 外部ステータス割り込み要因設定
    ; CR11 = 0h : すべての拡張E/S割り込み要因を完全に禁止する
    ; =========================================================
    mov al, 11              ; CR11Bの設定
    mov dx, MPSC1_B_CTRL
    out dx, al
    mov dx, MPSC2_B_CTRL
    out dx, al

    mov al, 0x00             ; Bチャネルの外部ステータス割り込み禁止
    mov dx, MPSC1_B_CTRL
    out dx, al
    mov dx, MPSC2_B_CTRL
    out dx, al
    
    ret
 
; =============================================================
; mpsc_write_both（MPSC#1と#2のチャンネルAのみ設定）
;   入力: AL = レジスタ番号, BL = 書き込み値
; =============================================================
mpsc_write_both:
    mov dx, MPSC1_A_CTRL
    out dx, al
    xchg al, bl
    out dx, al
    xchg al, bl
 
    mov dx, MPSC2_A_CTRL
    out dx, al
    xchg al, bl
    out dx, al
    xchg al, bl
 
    ret

; =================================================================
; Data
; =================================================================
msg_boot: db 0x0D,0x0A,"**  V53 RAM MONITOR for DVE-554 v0.3 2026-05-02  **",0x0D,0x0A,0
msg_load: db "Load HEX...",0
msg_ok:   db "OK",0
msg_go:   db "Go!",0

msg_prompt: db "> ", 0
msg_error:  db "Error", 0x0D, 0x0A, 0
msg_unknown:db "Unknown cmd", 0x0D, 0x0A, 0
msg_in_res: db "Val: ", 0
msg_done:   db " Done", 0x0D, 0x0A, 0
msg_bar:    db " | ", 0
msg_help:   db "Cmds: D <Seg> <Off>, L <Seg>, G <Seg> <Off>, W <Seg> <Off> <Val>, I <Port>, O <Port> <Val>, S <Start_port> <End_port>, T <Val> ?", 0x0D, 0x0A, 0
msg_scan_start: db "Scanning I/O (Press any key to abort)...", 0x0D, 0x0A, 0
msg_space:      db "  ", 0
msg_abort:      db "Aborted.", 0x0D, 0x0A, 0
msg_tick:   db "Tick: ", 0

ALIGN 2

; 変数
rx_buffer: times RX_BUF_SIZE db 0
head_ptr: dw 0
tail_ptr: dw 0

dump_seg: dw  0x0000  ; Dump: セグメント保存用
dump_off: dw  0x0000  ; Dump: オフセット保存用
load_seg: dw  0x0000  ; Load: ターゲットセグメント
tick_counter_lo: dw 0x0000  ; Tick: 下位16bit
tick_counter_hi: dw 0x0000  ; Tick: 上位16bit

intsys_flag: dw 0

; 割り込みフラグ
int0x20_flag: dw 0
int0x21_flag: dw 0
int0x22_flag: dw 0
int0x23_flag: dw 0
int0x24_flag: dw 0
int0x25_flag: dw 0
int0x26_flag: dw 0
int0x27_flag: dw 0

int0x28_flag: dw 0
int0x29_flag: dw 0
int0x2a_flag: dw 0
int0x2b_flag: dw 0
int0x2c_flag: dw 0
int0x2d_flag: dw 0
int0x2e_flag: dw 0
int0x2f_flag: dw 0

int0x30_flag: dw 0
int0x31_flag: dw 0
int0x32_flag: dw 0
int0x33_flag: dw 0
int0x34_flag: dw 0
int0x35_flag: dw 0
int0x36_flag: dw 0
int0x37_flag: dw 0