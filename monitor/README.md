# monitor

## 簡易モニタ

簡易モニタ([v53mon.asm](v53mon.asm))はROM用のモニタです。ブートストラップに必要な最低限の機能としています。

### モニタコマンド

| コマンド名 | 機能 | 使い方 | 実行例 |備考 |
| :--- | :--- | :--- | :--- | :--- |
| Go | 指定したアドレスからプログラムを実行する | G Segment Offset | G 2000 0000 | |
| Dump | 指定したアドレスからメモリの内容を表示する | D Segment Offset | D 2000 0000 | パラメタを省略した場合は次の64バイトを表示 |
| Load | 指定したセグメントのオフセット0000にIntel HEXファイルの内容をロードする | L Segment | L 2000 |パラメタを省略した場合は2000:0000にロード |

### ビルドの方法

1. nasmを使用してアセンブルします。

    ```
    nasm -f bin v53mon.asm -o v53mon.bin -l v53mon.lst
    ```

1. ROMのバイナリイメージを作成します

    以下のコマンドで rom_low_chip1.bin, rom_high_chip2.bin が生成されるので、それぞれをROMに書き込みます。

    ```
    python3 split_rom.py v53mon.bin
    ```
### IOベースアドレス

* 0x0F060 SCU

## RAM版モニタ

RAM版モニタ([v53_ram_mon.asm](v53_ram_mon.asm))は以下の機能を持ちます。ROM版モニタをベースにI/O操作、割り込みベクタとハンドラ、タイマーなどの実験的機能が追加されています。

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
    nasm -f bin v53_ram_mon.asm -o v53_ram_mon.bin -l v53_ram_mon.lst
    ```

1. ROMモニタでロードするためのHEXファイルを作成します

    ```
    objcopy -I binary -O ihex --change-addresses=0x0000 v53_ram_mon.bin v53_ram_mon.hex
    ```

### IOベースアドレス

* 0x0F060 SCU
* 0x0F070 TCU
* 0x0F080 ICU
* 0x00D8  USART (μPD71051)
* 0x00c8  PIC (μPD71059)
* 0x00e0  PPI (μPD71055)