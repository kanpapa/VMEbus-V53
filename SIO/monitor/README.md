# V53 monitor for DVE-554

## ROM版モニタ

ROM版モニタ([v53sio_mon.asm](v53sio_mon.asm))はROM書き込み用の簡易モニタです。ブートストラップに必要な最低限の機能としています。

### モニタコマンド

| コマンド名 | 機能 | 使い方 | 実行例 |備考 |
| :--- | :--- | :--- | :--- | :--- |
| Go | 指定したアドレスからプログラムを実行する | G Segment Offset | G 2000 0000 | |
| Dump | 指定したアドレスからメモリの内容を表示する | D Segment Offset | D 2000 0000 | パラメタを省略した場合は次の64バイトを表示 |
| Load | 指定したセグメントのオフセット0000にIntel HEXファイルの内容をロードする | L Segment | L 2000 |パラメタを省略した場合は2000:0000にロード |

### ビルドの方法

1. nasmを使用してアセンブルします。

    ```
    nasm -f bin v53sio_mon.asm -o v53sio_mon.bin -l v53sio_mon.lst
    ```

1. ROMにバイナリイメージを書き込みます

    DVE-554では27C1024を使用しているので生成されたv53sio_mon.binを10000hからROMに書き込みます。

## RAM版モニタ

RAM版モニタ([v53sio_ram_mon.asm](v53sio_ram_mon.asm))はROM版モニタをベースにI/O操作、割り込みベクタとハンドラ、タイマーなどの実験的機能が追加されています。

| コマンド名 | 機能 | 使い方 | 実行例 |備考 |
| :--- | :--- | :--- | :--- | :--- |
| Go | 指定したアドレスからプログラムを実行する | G Segment Offset | G 2000 0000 | |
| Dump | 指定したアドレスからメモリの内容を表示する | D Segment Offset | D 2000 0000 | パラメタを省略した場合は次の64バイトを表示 |
| Load | 指定したセグメントのオフセット0000にIntel HEXファイルの内容をロードする | L Segment | L 2000 |パラメタを省略した場合は2000:0000にロード |
| Input | 指定したI/Oアドレスから入力した値を表示する | I address | I 2000 | |
| Output| 指定したI/Oアドレスに指定した値を出力する | O address value | O 2000 00 | |
| Scan | 指定したI/Oアドレスの範囲でinp命令を実行し取得できた値が0FFH以外の場合にI/Oアドレスと値を表示する | S start end | S 0000 00FF | |
| Write | 指定したIOアドレスに値を書き込む | W Segment offset value  | W 3000 0000 44 | |
| Timer | 16進数で指定した時間×10msだけ待つ | T ms | T 1770 |パラメタを省略した場合はTickカウンタの値を表示する |
| Help | コマンドの一覧表示 | ? | | 

### ビルドの方法

1. nasmを使用してアセンブルします。

    ```
    nasm -f bin v53sio_ram_mon.asm -o v53sio_ram_mon.bin -l v53sio_ram_mon.lst
    ```

1. ROMモニタでロードするためのHEXファイルを作成します

    ```
    objcopy -I binary -O ihex --change-addresses=0x0000 v53sio_ram_mon.bin v53sio_ram_mon.hex
    ```