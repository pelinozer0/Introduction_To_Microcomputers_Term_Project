;===========================================================
; PROJE: PERDE KONTROL SISTEMI (SADECE POT + STEP + LCD)
; Islemci: PIC16F877A
; Derleyici: XC8 (PIC-AS) uyumlu
; ACIKLAMA: 
;   Bu program, bir potansiyometreden okunan analog degeri
;   0-100 arasinda bir yuzdeye cevirir. Step motoru, 
;   mevcut konumundan hedef konuma dogru hareket ettirir.
;   Durumu LCD ekranda gosterir.
;===========================================================

    PROCESSOR 16F877A
    #include <xc.inc>

    ;-----------------------------------------------------------
    ; CONFIG AYARLARI (Islemcinin donanim ayarlari)
    ;-----------------------------------------------------------
    CONFIG FOSC = HS        ; Yuksek Hizli Osilator (Kristal)
    CONFIG WDTE = OFF       ; Watchdog Timer Kapali (Kilitlenmeyi onleyici zamanlayici yok)
    CONFIG PWRTE = ON       ; Power-up Timer Acik (Guc geldiginde kararli olmasi icin bekle)
    CONFIG BOREN = ON       ; Brown-out Reset Acik (Voltaj duserse reset at)
    CONFIG LVP = OFF        ; Dusuk Voltaj Programlama Kapali
    CONFIG CPD = OFF        ; EEPROM Korumasi Kapali
    CONFIG WRT = OFF        ; Flash Yazma Korumasi Kapali
    CONFIG CP = OFF         ; Kod Korumasi Kapali

    ;-----------------------------------------------------------
    ; DEGISKENLER (RAM BELLEK ADRES ATAMALARI)
    ;-----------------------------------------------------------
    ; Islemcinin RAM belleginde degiskenler icin yer ayiriyoruz.
    ; EQU komutu bir etikete sabit bir deger/adres atar.
    
CURRENT_POS     EQU     0x20    ; Motorun su anki konumu (0-100 arasi)
TARGET_POS      EQU     0x21    ; Gitmesi gereken hedef konum (0-100 arasi)
ADC_SUM_L       EQU     0x30    ; ADC okumalarinin toplami (Alt 8 bit)
ADC_SUM_H       EQU     0x31    ; ADC okumalarinin toplami (Ust 8 bit)
ADC_COUNT       EQU     0x32    ; ADC dongu sayaci
AVG_RESULT      EQU     0x33    ; ADC ortalama sonucu
TMP_L           EQU     0x34    ; Matematiksel islemler icin gecici degisken (Low)
TMP_H           EQU     0x35    ; Matematiksel islemler icin gecici degisken (High)
MUL_CNT         EQU     0x36    ; Carpma islemi sayaci
DIFF_COUNT      EQU     0x37    ; Hedef ve Mevcut konum arasindaki fark
STEP_LOOP       EQU     0x38    ; Adim atma dongusu sayaci
STEP_INDEX      EQU     0x39    ; Step motorun hangi fazda oldugunu tutar (0-3)
D1              EQU     0x3A    ; Gecikme dongusu degiskeni 1
D2              EQU     0x3B    ; Gecikme dongusu degiskeni 2
LCD_TEMP        EQU     0x3D    ; LCD'ye veri gonderirken kullanilan gecici saklayici
HUNDREDS        EQU     0x3E    ; LCD'ye yazilacak sayinin Yuzler basamagi
TENS            EQU     0x3F    ; LCD'ye yazilacak sayinin Onlar basamagi
ONES            EQU     0x40    ; LCD'ye yazilacak sayinin Birler basamagi

    ;-----------------------------------------------------------
    ; PORT TANIMLARI
    ;-----------------------------------------------------------
    ; Kodun okunabilirligini artirmak icin portlara isim veriyoruz.
MOTOR_PORT      EQU     PORTB   ; Motor PORTB'ye bagli
MOTOR_TRIS      EQU     TRISB   ; Motor portunun giris/cikis ayari

    ; LCD Baglantilari: RD2=RS, RD3=EN, RD4-RD7=Data
#define LCD_PORT PORTD
#define LCD_RS   PORTD, 2
#define LCD_EN   PORTD, 3

    ;-----------------------------------------------------------
    ; PROGRAM BASLANGIC VEKTORU
    ;-----------------------------------------------------------
    PSECT code, abs
    ORG 0x00            ; Islemci acildiginda buradan baslar
    GOTO MAIN           ; Ana programa atla

;===========================================================
; ANA PROGRAM (KURULUM VE AYARLAR)
;===========================================================
MAIN:
    ; --- 1. Port Ayarlari ---
    BANKSEL TRISB       ; Bank 1'e gec (TRIS kaydedicileri icin)
    MOVLW   0xF0        ; Binary: 11110000 -> RB0-RB3 Cikis (0), RB4-RB7 Giris (1)
    MOVWF   TRISB       ; Ayari TRISB'ye yukle
    
    BANKSEL TRISD
    CLRF    TRISD       ; TRISD'yi temizle (0x00). Tum PORTD pinleri CIKIS oldu (LCD icin).
    
    BANKSEL TRISA
    BSF     TRISA, 0    ; RA0 pinini GIRIS yap (Potansiyometre buraya bagli)

    ; --- 2. ADC (Analog-Dijital Cevirici) Ayarlari ---
    BANKSEL ADCON1
    MOVLW   0x04        ; AN0 ve AN1 Analog giris olsun, Vref=Besleme voltaji
    MOVWF   ADCON1
    
    BANKSEL ADCON0
    MOVLW   0x41        ; Ayarlar: Fosc/8 hizi, Kanal 0 (AN0) secili, ADC Modulu ACIK
    MOVWF   ADCON0

    ; --- 3. Degiskenleri Sifirlama ---
    ; Baslangicta rastgele degerlerle acilmamasi icin temizlik yapiyoruz.
    BANKSEL CURRENT_POS ; Bank 0'a don (RAM degiskenleri icin)
    CLRF    CURRENT_POS ; Mevcut konumu 0 yap
    CLRF    TARGET_POS  ; Hedef konumu 0 yap
    CLRF    MOTOR_PORT  ; Motora giden enerjiyi kes
    CLRF    STEP_INDEX  ; Adim sirasini sifirla
    
    ; --- 4. LCD Ekran Baslatma ---
    BANKSEL PORTD
    CLRF    PORTD       ; Portu temizle
    CALL    Delay       ; LCD'nin elektrigi almasi icin biraz bekle
    CALL    LCD_Init    ; LCD'yi hazirla (4-bit moduna al, ayarlari yukle)
    CALL    LCD_Splash_Screen ; Ekrana "Curtain Control" yazisini bas

    CALL    Delay       ; Kullanici yaziyi gorsun diye bekle
    CALL    Delay

;===========================================================
; ANA DONGU (SONSUZ DONGU)
;===========================================================
LOOP:
    ; --- 1. Potansiyometreyi Oku ---
    ; Parazitleri engellemek icin ortalama alarak okur.
    CALL    Read_ADC_Smoothed   
    
    ; --- 2. Yuzdeye Cevir ---
    ; Okunan analog degeri (0-1023), yuzdeye (0-100) donusturur.
    CALL    Calculate_Percent   
    
    ; --- 3. Motoru Kontrol Et ---
    ; Mevcut konum ile hedef konumu kiyaslar ve motoru surer.
    CALL    Control_Motor       
    
    ; --- 4. Ekrani Guncelle ---
    ; Yeni yuzde degerini LCD'ye yazar.
    CALL    LCD_Update_Values   
    
    GOTO    LOOP        ; Basa don (Sonsuz Dongu)

;===========================================================
; ALT PROGRAM: ADC OKUMA (SMOOTHING / ORTALAMA ALMA)
; Amac: Sinyaldeki gurultuyu azaltmak icin 32 kere okuyup ortalamasini alir.
;===========================================================
Read_ADC_Smoothed:
    CLRF    ADC_SUM_L       ; Toplam degiskenlerini sifirla
    CLRF    ADC_SUM_H
    MOVLW   32              ; Dongu sayisi: 32
    MOVWF   ADC_COUNT
ADC_Loop:
    BANKSEL ADCON0
    BSF     ADCON0, 2       ; ADC cevrimini BASLAT (GO/DONE biti 1 yapilir)
Wait_ADC:
    BTFSC   ADCON0, 2       ; Cevrim bitti mi? (GO/DONE 0 oldu mu?)
    GOTO    Wait_ADC        ; Bitmediyse bekle

    MOVF    ADRESH, W       ; ADC sonucunun ust kismini al
    ADDWF   ADC_SUM_L, F    ; Toplama ekle
    BTFSC   STATUS, 0       ; Eger tasma varsa (Carry=1)...
    INCF    ADC_SUM_H, F    ; ...Ust byte'i 1 artir
    DECFSZ  ADC_COUNT, F    ; Sayaci azalt, 0 degilse devam et
    GOTO    ADC_Loop

    ; --- Ortalama Alma (Bolme Islemi) ---
    ; 32 adet sayiyi topladik. 32'ye bolmek icin sayiyi 5 kere saga kaydiriyoruz.
    ; (2^5 = 32)
    MOVLW   5
    MOVWF   ADC_COUNT
Shift_R:
    BCF     STATUS, 0       ; Carry temizle
    RRF     ADC_SUM_H, F    ; High byte'i saga kaydir
    RRF     ADC_SUM_L, F    ; Low byte'i saga kaydir
    DECFSZ  ADC_COUNT, F    ; 5 kere tekrarla
    GOTO    Shift_R

    MOVF    ADC_SUM_L, W    ; Sonucu W register'ina al
    MOVWF   AVG_RESULT      ; AVG_RESULT degiskenine kaydet
    RETURN

;===========================================================
; ALT PROGRAM: YUZDE HESAPLAMA
; Amac: 0-255 arasindaki ADC sonucunu 0-100 skala sistemine oturtur.
;===========================================================
Calculate_Percent:
    CLRF    TMP_L
    CLRF    TMP_H
    ; Burada basit bir oran oranti ve yuvarlama islemi yapiliyor.
    ; Matematiksel detay: (ADC * Katsayi) / Bolen
    MOVLW   25
    MOVWF   MUL_CNT
Mul_Loop:
    MOVF    AVG_RESULT, W
    ADDWF   TMP_L, F
    BTFSC   STATUS, 0
    INCF    TMP_H, F
    DECFSZ  MUL_CNT, F
    GOTO    Mul_Loop

    ; Yuvarlama icin ekleme
    MOVLW   32
    ADDWF   TMP_L, F
    BTFSC   STATUS, 0
    INCF    TMP_H, F

    ; Bolme islemi (Shift ile)
    MOVLW   6
    MOVWF   MUL_CNT
Div_Loop:
    BCF     STATUS, 0
    RRF     TMP_H, F
    RRF     TMP_L, F
    DECFSZ  MUL_CNT, F
    GOTO    Div_Loop

    MOVF    TMP_L, W
    MOVWF   TARGET_POS      ; Hesaplanan deger TARGET_POS'a yazildi

    ; --- Sinir Kontrolu (0 ile 100 arasinda tutma) ---
    ; Eger sonuc 5'ten kucukse 0 yap (titresim olmamasi icin)
    MOVF    AVG_RESULT, W
    SUBLW   5               
    BTFSC   STATUS, 0
    CLRF    TARGET_POS      

    ; Eger sonuc cok yuksekse 100'e sabitle
    MOVLW   250
    SUBWF   AVG_RESULT, W   
    BTFSC   STATUS, 0
    MOVLW   100
    BTFSC   STATUS, 0
    MOVWF   TARGET_POS      
    
    ; Guvenlik: Target > 100 ise 100 yap
    MOVLW   100
    SUBWF   TARGET_POS, W
    BTFSC   STATUS, 0       
    MOVWF   TARGET_POS      
    BTFSC   STATUS, 0
    GOTO    Set_Max
    RETURN
Set_Max:
    MOVLW   100
    MOVWF   TARGET_POS
    RETURN

;===========================================================
; ALT PROGRAM: MOTOR KONTROL MANTIGI
; Amac: Hedef konuma gore motoru ileri veya geri surmek.
;===========================================================
Control_Motor:
    BANKSEL ADCON0
    MOVLW   0x41            ; ADC kanalinin karismamasi icin garantiye al
    MOVWF   ADCON0

    ; Hedef ve Mevcut konum esit mi?
    MOVF    TARGET_POS, W
    SUBWF   CURRENT_POS, W
    BTFSC   STATUS, 2       ; Zero biti 1 ise (sonuc 0), sayilar esittir.
    RETURN                  ; Esitse hicbir sey yapma, geri don.

    ; Esit degilse, buyuk mu kucuk mu?
    BTFSS   STATUS, 0       ; Carry bit kontrolu
    GOTO    Move_Close      ; Carry=0 ise (Current < Target) -> Perdeyi Kapat (Ileri)
    GOTO    Move_Open       ; Carry=1 ise (Current > Target) -> Perdeyi Ac (Geri)

Move_Close: 
    ; Hedefe ulasmak icin kac adim lazim? (Fark hesabi)
    MOVF    CURRENT_POS, W
    SUBWF   TARGET_POS, W
    MOVWF   DIFF_COUNT
Loop_Close:
    ; Her %1'lik artis icin 10 adim at (Mekanik orana gore degisir)
    MOVLW   10
    MOVWF   STEP_LOOP
Step_Fwd_Loop:
    CALL    Step_Forward    ; Bir adim ileri git
    CALL    Delay           ; Motorun tepki vermesi icin bekle
    DECFSZ  STEP_LOOP, F    ; 10 adim bitti mi?
    GOTO    Step_Fwd_Loop
    INCF    CURRENT_POS, F  ; Konumu 1 artir
    DECFSZ  DIFF_COUNT, F   ; Hedefe vardik mi?
    GOTO    Loop_Close
    RETURN

Move_Open: 
    ; Geri yonde fark hesabi
    MOVF    TARGET_POS, W
    SUBWF   CURRENT_POS, W
    MOVWF   DIFF_COUNT
Loop_Open:
    MOVLW   10              ; Her %1 icin 10 adim
    MOVWF   STEP_LOOP
Step_Back_Loop:
    CALL    Step_Backward   ; Bir adim geri git
    CALL    Delay           ; Bekle
    DECFSZ  STEP_LOOP, F
    GOTO    Step_Back_Loop
    DECF    CURRENT_POS, F  ; Konumu 1 azalt
    DECFSZ  DIFF_COUNT, F   ; Hedefe vardik mi?
    GOTO    Loop_Open
    RETURN

;===========================================================
; ALT PROGRAM: STEP MOTOR SÜRME (ADIM TABLOSU)
; Amac: Motor sargilarina sirasiyla enerji vererek donmesini saglamak.
;===========================================================
Step_Forward:
    DECF    STEP_INDEX, F   ; Indeksi azalt (Sola donus gibi)
    MOVLW   0x03
    ANDWF   STEP_INDEX, F   ; Indeksi 0-3 arasinda tut (Mod alma islemi)
    CALL    Output_Step     ; Port'a gonder
    RETURN

Step_Backward:
    INCF    STEP_INDEX, F   ; Indeksi artir
    MOVLW   0x03
    ANDWF   STEP_INDEX, F   ; Indeksi 0-3 arasinda tut
    CALL    Output_Step     ; Port'a gonder
    RETURN

Output_Step:
    MOVF    STEP_INDEX, W   ; Indeks degerini W'ye al
    CALL    Step_Table      ; Tablodan karsiligini bul
    MOVWF   MOTOR_PORT      ; Degeri PORTB'ye yaz (Motor döner)
    RETURN

; Step Motor Bobin Siralamasi (Full Step)
Step_Table:
    ADDWF   PCL, F          ; Program sayacina ekle (Jump Table mantigi)
    RETLW   0x01   ; Adim 1: 0001
    RETLW   0x02   ; Adim 2: 0010
    RETLW   0x04   ; Adim 3: 0100
    RETLW   0x08   ; Adim 4: 1000

;===========================================================
; ALT PROGRAM: GECIKME (DELAY)
; Amac: Islemciyi bos yere mesgul ederek zaman gecirmek.
;===========================================================
Delay:
    MOVLW   5               ; Dis dongu sayisi
    MOVWF   D1
Del_Loop:
    MOVLW   200             ; Ic dongu sayisi
    MOVWF   D2
Del_Inner:
    DECFSZ  D2, F           ; D2'yi azalt, 0 olunca atla
    GOTO    Del_Inner       ; 0 degilse don
    DECFSZ  D1, F           ; D1'i azalt
    GOTO    Del_Loop        ; 0 degilse basa don
    RETURN

;===========================================================
; LCD KUTUPHANESI (EKRAN KONTROL ALT PROGRAMLARI)
;===========================================================

LCD_Init:
    ; --- LCD Baslatma Proseduru (Datasheet'e gore) ---
    CALL    Delay           ; LCD'nin voltaji oturana kadar bekle
    
    ; 4-Bit Moduna Gecis (Ozel bir siralama gerekir)
    MOVLW   0x03
    CALL    LCD_Nibble      ; Reset sinyali 1
    CALL    Delay_Short
    MOVLW   0x03
    CALL    LCD_Nibble      ; Reset sinyali 2
    CALL    Delay_Short
    MOVLW   0x03
    CALL    LCD_Nibble      ; Reset sinyali 3
    CALL    Delay_Short
    MOVLW   0x02            ; 4-bit moda gec komutu
    CALL    LCD_Nibble
    CALL    Delay_Short
    
    ; LCD Yapilandirma Komutlari
    MOVLW   0x28            ; 4-bit iletisim, 2 satir, 5x7 nokta karakter
    CALL    LCD_Cmd
    MOVLW   0x0C            ; Ekrani AC, Kursoro (imleci) GIZLE
    CALL    LCD_Cmd
    MOVLW   0x06            ; Her karakter yazildiginda imleci Saga Kaydir
    CALL    LCD_Cmd
    MOVLW   0x01            ; Ekrani TEMIZLE
    CALL    LCD_Cmd
    CALL    Delay
    RETURN

LCD_Splash_Screen:
    ; --- Acilis Yazisi ---
    ; Satir 1: "Curtain Control"
    MOVLW   0x80            ; 1. Satir baslangic adresi
    CALL    LCD_Cmd
    MOVLW   'C'             ; Harfleri tek tek gonderiyoruz
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
    MOVLW   ' '
    CALL    LCD_Dat
    MOVLW   'C'
    CALL    LCD_Dat
    MOVLW   't'
    CALL    LCD_Dat
    MOVLW   'r'
    CALL    LCD_Dat
    MOVLW   'l'
    CALL    LCD_Dat
    
    ; --- Satir 2: Sabit Etiketler ---
    MOVLW   0xC8            ; 2. Satirin ortasi
    CALL    LCD_Cmd
    MOVLW   'P'
    CALL    LCD_Dat
    MOVLW   ':'
    CALL    LCD_Dat
    RETURN

LCD_Update_Values:
    ; --- Deger Guncelleme ---
    ; Ekranda sadece degisen rakamlari gunceller.
    MOVLW   0xCA            ; 2. Satir, yuzde isaretinin yanina git
    CALL    LCD_Cmd
    MOVF    CURRENT_POS, W  ; Mevcut yuzdeyi W'ye al
    CALL    Bin_To_Dec_LCD  ; Decimal'e cevirip ekrana bas
    MOVLW   '%'             ; Yuzde isaretini koy
    CALL    LCD_Dat
    RETURN

Bin_To_Dec_LCD:
    MOVWF   ADC_COUNT       ; Sayiyi sakla
    CLRF    HUNDREDS        ; Basamaklari sifirla
    CLRF    TENS
    CLRF    ONES
    
    ; --- Yuzler Basamagi Bulma ---
Calc_100:
    MOVLW   100
    SUBWF   ADC_COUNT, W    ; Sayidan 100 cikar
    BTFSS   STATUS, 0       ; Negatif oldu mu? (Carry 0 mi?)
    GOTO    Calc_10         ; Evetse 100'ler bitti, 10'lara gec
    MOVWF   ADC_COUNT       ; Hayirsa kalan sayiyi sakla
    INCF    HUNDREDS, F     ; Yuzler basamagini 1 artir
    GOTO    Calc_100        ; Tekrar dene
    
    ; --- Onlar Basamagi Bulma ---
Calc_10:
    MOVLW   10
    SUBWF   ADC_COUNT, W
    BTFSS   STATUS, 0
    GOTO    Calc_1
    MOVWF   ADC_COUNT
    INCF    TENS, F
    GOTO    Calc_10

    ; --- Birler Basamagi ---
Calc_1:
    MOVF    ADC_COUNT, W    ; Kalan sayi birler basamagidir
    MOVWF   ONES
    
    ; --- LCD'ye Yazdirma ---
    ; Sayilari ASCII koduna cevirmek icin 0x30 (Decimal 48) eklenir.
    ; Ornek: 0 sayisi -> ASCII '0' (0x30), 1 sayisi -> ASCII '1' (0x31)
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

; --- LCD'ye Komut Gonderen Alt Program ---
LCD_Cmd:
    MOVWF   LCD_TEMP        ; Komutu sakla
    MOVF    LCD_TEMP, W
    ANDLW   0xF0            ; Ust 4 biti maskele
    MOVWF   PORTD           ; Ust 4 biti Porta koy
    BCF     LCD_RS          ; RS=0 (Komut Modu)
    CALL    Pulse           ; Enable sinyali ver (Gonder)
    SWAPF   LCD_TEMP, W     ; Alt ve Ust 4 biti yer degistir
    ANDLW   0xF0            ; Yeni ust 4 biti (eski alt) maskele
    MOVWF   PORTD           ; Porta koy
    BCF     LCD_RS          ; RS=0
    CALL    Pulse           ; Enable sinyali ver
    CALL    Delay_Short     ; LCD'nin komutu i?lemesi için bekle
    RETURN

; --- LCD'ye Veri (Harf/Sayi) Gonderen Alt Program ---
LCD_Dat:
    MOVWF   LCD_TEMP        ; Veriyi sakla
    MOVF    LCD_TEMP, W
    ANDLW   0xF0            ; Ust 4 bit
    MOVWF   PORTD
    BSF     LCD_RS          ; RS=1 (Veri Modu - Harf yaziyoruz)
    CALL    Pulse
    SWAPF   LCD_TEMP, W     ; Alt 4 bite gec
    ANDLW   0xF0
    MOVWF   PORTD
    BSF     LCD_RS          ; RS=1
    CALL    Pulse
    CALL    Delay_Short
    RETURN

; --- Sadece 4-bit Veri Gonderme (Baslangic/Init icin) ---
LCD_Nibble:
    MOVWF   LCD_TEMP
    SWAPF   LCD_TEMP, W
    ANDLW   0xF0
    MOVWF   PORTD
    BCF     LCD_RS
    CALL    Pulse
    RETURN

; --- LCD Enable Pini Tetikleme ---
Pulse:
    BSF     LCD_EN          ; Enable pinini 1 yap
    NOP                     ; Cok kisa bekle (Islemci hizi dengesi)
    BCF     LCD_EN          ; Enable pinini 0 yap (Dusen kenarda veri alinir)
    RETURN

Delay_Short:
    MOVLW   5
    MOVWF   D2
Dly_S:
    DECFSZ  D2, F
    GOTO    Dly_S
    RETURN

    END