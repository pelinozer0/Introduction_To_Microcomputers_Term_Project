;******************************************************************************
;   PROJECT: Term Project - Board #2 (Curtain Control System)
;   HARDWARE: PIC16F877A - INTERRUPT VERSIYONU (SYNC FIX)
;   CLOCK:   4 MHz
;
;   AMAÇ:
;   - Board #2 perde kontrol sistemini yönetir.
;   - Potansiyometreden hedef perde yüzdesi (0-100) üretilir.
;   - LDR ile ???k seviyesi izlenir; e?ik alt? ise perde otomatik kapan?r.
;   - Step motor ile CURTAIN_POS güncellenerek hedefe do?ru hareket ettirilir.
;   - UART üzerinden PC ile haberle?ir:
;       0xB0 -> Set Curtain Target (sonraki byte TARGET_POS)
;       0xA1 -> Get Curtain Status (CURTAIN_POS gönder)
;       0xA3 -> Get Light Intensity (LDR_VAL gönder)
;******************************************************************************

    PROCESSOR 16F877A
    #include <xc.inc>

    ; --- CONFIGURATION BITS ---
    CONFIG FOSC = HS, WDTE = OFF, PWRTE = ON, BOREN = OFF, LVP = OFF, CPD = OFF, WRT = OFF, CP = OFF

;------------------------------------------------------------------------------
; DEGISKENLER (RAM)
;------------------------------------------------------------------------------
    PSECT udata_bank0

    ; --- Sistem Durumu (Uygulama ana de?i?kenleri) ---
    CURTAIN_POS:    DS 1    ; Mevcut perde konumu (%) -> 0 aç?k, 100 kapal?
    TARGET_POS:     DS 1    ; Hedef perde konumu (%)  -> komut/pot/LDR ile güncellenir
    LDR_VAL:        DS 1    ; I??k sensörü de?eri (0..255 ölçe?inde tutulur)
    POT_VAL:        DS 1    ; Potansiyometre (AVG_RESULT) (not: burada fiilen AVG_RESULT kullan?l?yor)

    ; --- Motor Kontrol (step motor sürme yard?mc?lar?) ---
    STEP_INDEX:     DS 1    ; Step tablosu indeksi (0..3)
    DIFF_COUNT:     DS 1    ; Hedef ile mevcut aras?ndaki fark kadar yüzde ad?m? sayac?
    STEP_LOOP:      DS 1    ; Her 1% için at?lacak step say?s? döngü sayac? (10 step / 1%)
    MOTOR_PORT_VAR: DS 1    ; (Opsiyonel) motor ç?k??? için ara de?i?ken (bu kodda do?rudan PORTB yaz?l?yor)

    ; --- UART ve State Machine ---
    RX_TEMP:        DS 1    ; UART?tan gelen son byte
    CMD_STATE:      DS 1    ; UART komut durum de?i?keni:
                             ; 0: komut bekleniyor
                             ; 1: SET komutundan sonra veri byte'? bekleniyor

    ; --- Hesaplama ve Gecikme (ADC ortalama / yüzde hesab? / delay) ---
    ADC_SUM_L:      DS 1    ; ADC toplam (low byte)
    ADC_SUM_H:      DS 1    ; ADC toplam (high byte)
    ADC_COUNT:      DS 1    ; döngü sayaçlar? / geçici kullan?m
    AVG_RESULT:     DS 1    ; 32 örnek ortalamas?ndan ç?kan ADRESH temelli sonuç
    TMP_L:          DS 1    ; yüzde hesaplar? için ara de?er (low)
    TMP_H:          DS 1    ; yüzde hesaplar? için ara de?er (high)
    MUL_CNT:        DS 1    ; çarpma/bölme döngü sayac?
    LAST_POT_POS:   DS 1    ; pot ile en son hesaplanan % de?er (de?i?im takibi)
    NEW_POT_VAL:    DS 1    ; yeni hesaplanan % de?er
    D1:             DS 1    ; Delay döngüsü sayac? 1
    D2:             DS 1    ; Delay döngüsü sayac? 2

    ; --- LCD ile ilgili geçici de?i?kenler ---
    LCD_TEMP:       DS 1    ; LCD komut/veri gönderiminde geçici
    HUNDREDS:       DS 1    ; Bin->Dec dönü?ümü: yüzler
    TENS:           DS 1    ; Bin->Dec dönü?ümü: onlar
    ONES:           DS 1    ; Bin->Dec dönü?ümü: birler

    ; --- Kesme Context (ISR içerisinde W ve STATUS saklama) ---
    PSECT udata_shr
    W_ISR:          DS 1
    STATUS_ISR:     DS 1

;==============================================================================
; RESET VEKTORU
;==============================================================================
    PSECT code, abs
    ORG 0x0000
    GOTO    MAIN          ; Reset sonras? ana programa git

    ORG 0x0004
    ; --- INTERRUPT SERVIS RUTINI (ISR) ---
    ; Amaç: UART RX kesmesi geldi?inde güvenli ?ekilde handler ça??rmak
    ; Not: W ve STATUS saklan?p geri yükleniyor (context save/restore)
    MOVWF   W_ISR
    SWAPF   STATUS, W
    MOVWF   STATUS_ISR

    ; Bank0'a dön (ISR içinde do?ru bank eri?imi için)
    BCF     STATUS, 5
    BCF     STATUS, 6

    ; UART RX interrupt flag (RCIF) kontrolü: PIR1 bit5
    BANKSEL PIR1
    BTFSC   PIR1, 5
    CALL    UART_RX_HANDLER

    ; Context Restore
    SWAPF   STATUS_ISR, W
    MOVWF   STATUS
    SWAPF   W_ISR, F
    SWAPF   W_ISR, W
    RETFIE                 ; kesmeden dönü? (GIE tekrar aktif)

;==============================================================================
; UART RX HANDLER (STATE MACHINE)
;==============================================================================
UART_RX_HANDLER:
    ; UART receive register okunur; RCREG okununca RCIF otomatik temizlenir.
    BANKSEL RCREG
    MOVF    RCREG, W
    MOVWF   RX_TEMP     ; Gelen veriyi al

    ; --- DURUM KONTROLU ---
    ; CMD_STATE == 1 ise: bir önceki byte SET komutuydu, ?imdi gelen byte TARGET_POS olacak.
    MOVF    CMD_STATE, W
    SUBLW   1
    BTFSC   STATUS, 2
    GOTO    PROCESS_SET_DATA

    ; --- KOMUT MODU ---
    ; Bu modda RX_TEMP bir komut byte'?d?r.

    ; 0xB0 -> SET CURTAIN (sonraki byte hedef yüzde)
    MOVF    RX_TEMP, W
    XORLW   0xB0
    BTFSC   STATUS, 2
    GOTO    PREPARE_SET_TARGET

    ; 0xA1 -> GET CURTAIN STATUS (CURTAIN_POS gönder)
    MOVF    RX_TEMP, W
    XORLW   0xA1
    BTFSC   STATUS, 2
    GOTO    SEND_CURTAIN_STATUS

    ; 0xA3 -> GET LIGHT INTENSITY (LDR_VAL gönder)
    MOVF    RX_TEMP, W
    XORLW   0xA3
    BTFSC   STATUS, 2
    GOTO    SEND_LDR_VAL

    ; Tan?ms?z komut ise bir ?ey yapmadan ç?k
    RETURN

PREPARE_SET_TARGET:
    ; Sonraki RX byte'?n? veri olarak kabul et (TARGET_POS)
    MOVLW   1
    MOVWF   CMD_STATE
    RETURN

PROCESS_SET_DATA:
    ; Gelen veri byte'?n? hedef perde yüzdesi olarak kaydet
    MOVF    RX_TEMP, W
    MOVWF   TARGET_POS
    CLRF    CMD_STATE      ; tekrar komut moduna dön
    RETURN

SEND_CURTAIN_STATUS:
    ; Mevcut perde konumunu tek byte olarak gönder
    MOVF    CURTAIN_POS, W
    CALL    UART_TX
    RETURN

SEND_LDR_VAL:
    ; I??k sensörü de?erini tek byte olarak gönder
    MOVF    LDR_VAL, W
    CALL    UART_TX
    RETURN

UART_TX:
    ; TXREG yazmadan önce TRMT (TXSTA bit1) = 1 olana kadar bekle
    BANKSEL TXSTA
    BTFSS   TXSTA, 1
    GOTO    $-1
    BANKSEL TXREG
    MOVWF   TXREG
    BANKSEL PORTB
    RETURN

;==============================================================================
; ANA PROGRAM
;==============================================================================
MAIN:
    ; --- Bank 1: TRIS ve baz? konfigürasyon register ayarlar? ---
    BSF     STATUS, 5

    ; PORTB motor ç?k?? (step motor bobinleri)
    CLRF    TRISB

    ; PORTD LCD veri/ctrl (bu kodda 4-bit nibble ta??nmas? üst nibble üzerinden yap?l?yor)
    CLRF    TRISD

    ; RA0: Potansiyometre analog giri?
    BSF     TRISA, 0

    ; RA1: LDR analog giri?
    BSF     TRISA, 1

    ; UART PINS
    ; RC6: TX output, RC7: RX input
    BCF     TRISC, 6
    BSF     TRISC, 7

    ; ADC Ayari
    ; ADCON1=0x04 -> AN0, AN1 analog; di?erleri dijital, referanslar default
    MOVLW   0x04
    MOVWF   ADCON1

    ; UART 9600 Baud (4MHz, BRGH=1, SPBRG=25)
    MOVLW   25
    MOVWF   SPBRG
    BSF     TXSTA, 2    ; BRGH=1
    BCF     TXSTA, 4    ; SYNC=0 (asenkron)
    BSF     TXSTA, 5    ; TXEN=1

    ; KESMELERI AC
    ; PIE1.RCIE = 1 -> UART RX interrupt enable
    BSF     PIE1, 5

    ; --- Bank 0: çevresel modülleri aktif et ---
    BCF     STATUS, 5
    BSF     RCSTA, 7    ; SPEN=1 (serial port enable)
    BSF     RCSTA, 4    ; CREN=1 (continuous receive)

    ; ADCON0 = 0x81 -> ADC aç, kanal seçimi ba?lang?ç (AN0), Fosc/32 vb.
    MOVLW   0x81
    MOVWF   ADCON0

    ; Global interrupt enable zinciri
    BSF     INTCON, 6   ; PEIE (peripheral interrupts enable)
    BSF     INTCON, 7   ; GIE (global interrupts enable)

    ; Ba?lang?ç temizli?i
    CLRF    PORTB
    CLRF    PORTD
    CLRF    CMD_STATE

    ; LCD Baslat (ba?lang?ç gecikmesi ve init)
    CALL    Delay
    CALL    LCD_Init
    CALL    LCD_Splash_Screen

LOOP:
    ; 1) Potansiyometre Oku -> hedef yüzdesini üret (TARGET_POS)
    CALL    Read_ADC_Smoothed
    CALL    Calculate_Percent

    ; 2) LDR Oku -> e?ik alt? ise perdeyi kapat (TARGET_POS=100)
    CALL    Light_Dependent_Resistor

    ; 3) Motor Kontrol -> CURTAIN_POS'u TARGET_POS'a yakla?t?r
    CALL    Control_Motor

    ; 4) LCD Guncelle -> ekrana LDR ve CURTAIN_POS yaz
    CALL    LCD_Update_Values

    GOTO    LOOP

;------------------------------------------------------------------------------
; ALT PROGRAMLAR
;------------------------------------------------------------------------------

Read_ADC_Smoothed:
    ; Amaç: Potansiyometre için ADC okumas?n? yumu?atmak (32 örnek ortalamas?)
    ; Yöntem: ADRESH 32 kez toplan?r, sonra /32 için 5 bit sa?a kayd?r?l?r.
    CLRF    ADC_SUM_L
    CLRF    ADC_SUM_H
    MOVLW   32
    MOVWF   ADC_COUNT
ADC_Loop:
    BANKSEL ADCON0
    MOVLW   0x41        ; Kanal seçimi: AN0 (pot), ADC ON (bit0=1) varsay?m? ile
    MOVWF   ADCON0
    BSF     ADCON0, 2   ; GO/DONE=1 -> dönü?üm ba?lat
Wait_ADC:
    BTFSC   ADCON0, 2   ; GO/DONE=1 kald?kça bekle
    GOTO    Wait_ADC

    ; Yaln?zca ADRESH kullan?l?yor (8-bit hassasiyet)
    MOVF    ADRESH, W
    ADDWF   ADC_SUM_L, F
    BTFSC   STATUS, 0
    INCF    ADC_SUM_H, F

    DECFSZ  ADC_COUNT, F
    GOTO    ADC_Loop

    ; /32 => 5 kez sa?a kayd?r
    MOVLW   5
    MOVWF   ADC_COUNT
Shift_R:
    BCF     STATUS, 0
    RRF     ADC_SUM_H, F
    RRF     ADC_SUM_L, F
    DECFSZ  ADC_COUNT, F
    GOTO    Shift_R

    MOVF    ADC_SUM_L, W
    MOVWF   AVG_RESULT
    RETURN

Calculate_Percent:
    ; Amaç: Pot de?eri (AVG_RESULT) -> 0..100 aras? yüzdeye ölçeklemek
    ; Yakla??m: sabit katsay?larla ölçek + yuvarlama + alt/üst s?n?r + de?i?im kontrolü
    CLRF    TMP_L
    CLRF    TMP_H

    ; TMP += AVG_RESULT * 25 (basit tekrar toplama ile çarpma)
    MOVLW   25
    MOVWF   MUL_CNT
Mul_Loop:
    MOVF    AVG_RESULT, W
    ADDWF   TMP_L, F
    BTFSC   STATUS, 0
    INCF    TMP_H, F
    DECFSZ  MUL_CNT, F
    GOTO    Mul_Loop

    ; Yuvarlama için +32 (sonra >>6 yap?laca?? için yar?m LSB)
    MOVLW   32
    ADDWF   TMP_L, F
    BTFSC   STATUS, 0
    INCF    TMP_H, F

    ; /64 => 6 kez sa?a kayd?r
    MOVLW   6
    MOVWF   MUL_CNT
Div_Loop:
    BCF     STATUS, 0
    RRF     TMP_H, F
    RRF     TMP_L, F
    DECFSZ  MUL_CNT, F
    GOTO    Div_Loop

    MOVF    TMP_L, W
    MOVWF   NEW_POT_VAL

    ; Alt Sinir: AVG_RESULT <= 5 ise NEW_POT_VAL = 0
    MOVF    AVG_RESULT, W
    SUBLW   5
    BTFSC   STATUS, 0
    CLRF    NEW_POT_VAL

    ; Ust Sinir: NEW_POT_VAL > 100 ise 100'e sabitle
    MOVF    NEW_POT_VAL, W
    SUBLW   100
    BTFSS   STATUS, 0
    GOTO    Set_Max_Fix
    GOTO    Check_Change
Set_Max_Fix:
    MOVLW   100
    MOVWF   NEW_POT_VAL

Check_Change:
    ; Pot de?eri de?i?mediyse hedefi güncelleme (gereksiz motor hareketini azalt?r)
    MOVF    NEW_POT_VAL, W
    SUBWF   LAST_POT_POS, W
    BTFSC   STATUS, 2
    RETURN

    ; De?i?tiyse TARGET_POS ve LAST_POT_POS güncellenir
    MOVF    NEW_POT_VAL, W
    MOVWF   TARGET_POS
    MOVWF   LAST_POT_POS
    RETURN

Light_Dependent_Resistor:
    ; Amaç: AN1 (LDR) üzerinden ???k ölç ve e?ik alt?na dü?ünce perdeyi kapat
    BANKSEL ADCON0
    MOVLW   0x49        ; Kanal: AN1 (LDR) seçimi
    MOVWF   ADCON0

    ; K?sa acquisition bekleme (basit gecikme)
    MOVLW   5
    MOVWF   D1
LDR_Acq:
    DECFSZ  D1, F
    GOTO    LDR_Acq

    ; ADC dönü?ümü ba?lat
    BSF     ADCON0, 2
Wait_LDR:
    BTFSC   ADCON0, 2
    GOTO    Wait_LDR

    ; ADRESH okunur
    MOVF    ADRESH, W

    ; Basit dönü?türme/temizleme: ADRESH > 250 ise 0'a çekme
    SUBLW   250
    BTFSS   STATUS, 0
    MOVLW   0
    MOVWF   LDR_VAL

    ; Esik Kontrolu (87):
    ; LDR_VAL < 87 ise perdeyi tamamen kapat (TARGET_POS=100)
    MOVLW   87
    SUBWF   LDR_VAL, W
    BTFSS   STATUS, 0
    GOTO    Close_Curtain
    RETURN

Close_Curtain:
    MOVLW   100
    MOVWF   TARGET_POS
    ; Pot de?i?im kontrolünü resetlemek için LAST_POT_POS özel de?ere çekilir
    MOVLW   0xFF
    MOVWF   LAST_POT_POS
    RETURN

Control_Motor:
    ; Amaç: TARGET_POS ile CURTAIN_POS farkl?ysa motoru ilgili yönde sürmek
    ; 1% ba??na 10 step uygulan?r (10 step/%)
    MOVF    TARGET_POS, W
    SUBWF   CURTAIN_POS, W
    BTFSC   STATUS, 2
    RETURN            ; hedef=mevcut ise ç?k

    ; Carry durumuna göre yön seçimi:
    ; E?er CURTAIN_POS < TARGET_POS ise kapamaya git (Close)
    BTFSS   STATUS, 0
    GOTO    Move_Close
    GOTO    Move_Open

Move_Close:
    ; DIFF_COUNT = TARGET_POS - CURTAIN_POS
    MOVF    CURTAIN_POS, W
    SUBWF   TARGET_POS, W
    MOVWF   DIFF_COUNT

Loop_Close:
    ; 1% için 10 step ileri
    MOVLW   10
    MOVWF   STEP_LOOP
Step_Fwd_Loop:
    CALL    Step_Forward
    CALL    Delay
    DECFSZ  STEP_LOOP, F
    GOTO    Step_Fwd_Loop

    INCF    CURTAIN_POS, F         ; % +1
    DECFSZ  DIFF_COUNT, F
    GOTO    Loop_Close
    RETURN

Move_Open:
    ; DIFF_COUNT = CURTAIN_POS - TARGET_POS
    MOVF    TARGET_POS, W
    SUBWF   CURTAIN_POS, W
    MOVWF   DIFF_COUNT

Loop_Open:
    ; 1% için 10 step geri
    MOVLW   10
    MOVWF   STEP_LOOP
Step_Back_Loop:
    CALL    Step_Backward
    CALL    Delay
    DECFSZ  STEP_LOOP, F
    GOTO    Step_Back_Loop

    DECF    CURTAIN_POS, F         ; % -1
    DECFSZ  DIFF_COUNT, F
    GOTO    Loop_Open
    RETURN

Step_Forward:
    ; Step index azalt?larak tabloya göre CW/CCW yön belirlenir
    DECF    STEP_INDEX, F
    MOVLW   0x03
    ANDWF   STEP_INDEX, F
    CALL    Output_Step
    RETURN

Step_Backward:
    ; Step index art?r?larak ters yönde döndürme
    INCF    STEP_INDEX, F
    MOVLW   0x03
    ANDWF   STEP_INDEX, F
    CALL    Output_Step
    RETURN

Output_Step:
    ; Step tablosundan al?nan mask PORTB'ye yaz?l?r (bobin sürme)
    MOVF    STEP_INDEX, W
    CALL    Step_Table
    MOVWF   PORTB
    RETURN

Step_Table:
    ; 4-ad?ml? tek bobin sürme tablosu
    ; 0->0001, 1->0010, 2->0100, 3->1000
    ADDWF   PCL, F
    RETLW   0x01
    RETLW   0x02
    RETLW   0x04
    RETLW   0x08

Delay:
    ; Basit yaz?l?msal gecikme (motor step h?z?n? belirler)
    MOVLW   5
    MOVWF   D1
Del_Loop:
    MOVLW   200
    MOVWF   D2
Del_Inner:
    DECFSZ  D2, F
    GOTO    Del_Inner
    DECFSZ  D1, F
    GOTO    Del_Loop
    RETURN

;------------------------------------------------------------------------------
; LCD Fonksiyonlar? (HD44780 benzeri, 4-bit aktar?m mant???)
; Not: Bu kod PORTD üst nibble üzerinden veri ta??r; RS=RD2, EN=RD3 kullan?lm??t?r.
;------------------------------------------------------------------------------

LCD_Init:
    ; LCD ba?lang?ç s?ralamas? (4-bit moda geçi? + temel ayarlar)
    CALL    Delay
    MOVLW   0x03
    CALL    LCD_Nibble
    CALL    Delay_Short
    MOVLW   0x03
    CALL    LCD_Nibble
    CALL    Delay_Short
    MOVLW   0x03
    CALL    LCD_Nibble
    CALL    Delay_Short
    MOVLW   0x02
    CALL    LCD_Nibble
    CALL    Delay_Short

    MOVLW   0x28        ; 4-bit, 2 sat?r, 5x8 font
    CALL    LCD_Cmd
    MOVLW   0x0C        ; display on, cursor off
    CALL    LCD_Cmd
    MOVLW   0x06        ; entry mode
    CALL    LCD_Cmd
    MOVLW   0x01        ; clear display
    CALL    LCD_Cmd
    CALL    Delay
    RETURN

LCD_Splash_Screen:
    ; Ba?lang?çta k?sa bilgilendirme yaz?s?
    MOVLW   0x80
    CALL    LCD_Cmd
    MOVLW   'C'
    CALL    LCD_Dat
    MOVLW   'u'
    CALL    LCD_Dat
    MOVLW   'r'
    CALL    LCD_Dat
    MOVLW   't'
    CALL    LCD_Dat
    MOVLW   'a'
    CALL    LCD_Dat
    MOVLW   'i'
    CALL    LCD_Dat
    MOVLW   'n'
    CALL    LCD_Dat

    MOVLW   0xC0
    CALL    LCD_Cmd
    MOVLW   'L'
    CALL    LCD_Dat
    MOVLW   ' '
    CALL    LCD_Dat

    MOVLW   0xC8
    CALL    LCD_Cmd
    MOVLW   'P'
    CALL    LCD_Dat
    MOVLW   ' '
    CALL    LCD_Dat
    RETURN

LCD_Update_Values:
    ; LCD üzerinde LDR ve Curtain Position gösterimi
    ; Konumlar sabit cursor adreslerine yaz?l?r
    MOVLW   0xC2
    CALL    LCD_Cmd
    MOVF    LDR_VAL, W
    CALL    Bin_To_Dec_LCD

    MOVLW   0xCA
    CALL    LCD_Cmd
    MOVF    CURTAIN_POS, W
    CALL    Bin_To_Dec_LCD
    MOVLW   '%'
    CALL    LCD_Dat
    RETURN

Bin_To_Dec_LCD:
    ; 0..255 byte de?eri yüzler-onlar-birler olarak ASCII basar
    MOVWF   ADC_COUNT
    CLRF    HUNDREDS
    CLRF    TENS
    CLRF    ONES
Calc_100:
    MOVLW   100
    SUBWF   ADC_COUNT, W
    BTFSS   STATUS, 0
    GOTO    Calc_10
    MOVWF   ADC_COUNT
    INCF    HUNDREDS, F
    GOTO    Calc_100
Calc_10:
    MOVLW   10
    SUBWF   ADC_COUNT, W
    BTFSS   STATUS, 0
    GOTO    Calc_1
    MOVWF   ADC_COUNT
    INCF    TENS, F
    GOTO    Calc_10
Calc_1:
    MOVF    ADC_COUNT, W
    MOVWF   ONES

    ; ASCII '0' (0x30) ekleyerek karakter bas?l?r
    MOVLW   0x30
    ADDWF   HUNDREDS, W
    CALL    LCD_Dat
    MOVLW   0x30
    ADDWF   TENS, W
    CALL    LCD_Dat
    MOVLW   0x30
    ADDWF   ONES, W
    CALL    LCD_Dat
    RETURN

LCD_Cmd:
    ; Komut gönderimi (RS=0), üst nibble sonra alt nibble
    MOVWF   LCD_TEMP
    MOVF    LCD_TEMP, W
    ANDLW   0xF0
    MOVWF   PORTD
    BCF     PORTD, 2    ; RS=0
    CALL    Pulse
    SWAPF   LCD_TEMP, W
    ANDLW   0xF0
    MOVWF   PORTD
    BCF     PORTD, 2
    CALL    Pulse
    CALL    Delay_Short
    RETURN

LCD_Dat:
    ; Veri gönderimi (RS=1), üst nibble sonra alt nibble
    MOVWF   LCD_TEMP
    MOVF    LCD_TEMP, W
    ANDLW   0xF0
    MOVWF   PORTD
    BSF     PORTD, 2    ; RS=1
    CALL    Pulse
    SWAPF   LCD_TEMP, W
    ANDLW   0xF0
    MOVWF   PORTD
    BSF     PORTD, 2
    CALL    Pulse
    CALL    Delay_Short
    RETURN

LCD_Nibble:
    ; 4-bit moda geçi?te kullan?lan nibble yaz?m?
    MOVWF   LCD_TEMP
    SWAPF   LCD_TEMP, W
    ANDLW   0xF0
    MOVWF   PORTD
    BCF     PORTD, 2
    CALL    Pulse
    RETURN

Pulse:
    ; EN darbesi (LCD latch)
    BSF     PORTD, 3    ; EN=1
    NOP
    BCF     PORTD, 3    ; EN=0
    RETURN

Delay_Short:
    ; LCD için k?sa gecikme
    MOVLW   5
    MOVWF   D2
    DECFSZ  D2, F
    GOTO    $-1
    RETURN

    END
