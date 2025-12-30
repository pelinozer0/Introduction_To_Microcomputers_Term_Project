;******************************************************************************
; UNIVERSITY: ESOGU - Electrical & Electronics / Computer Engineering
; COURSE: Introduction to Microcomputers (Term Project)
;
; PROJECT: Home Automation System - Board 1 (Air Conditioner Control)
; STUDENT: Aybüke Beyza Duman
; ID: 151220202022
; DATE: December 2025
;
; DESCRIPTION:
;   This assembly language program implements the firmware for Board #1 of the 
;   Home Automation System project. It utilizes a PIC16F877A microcontroller 
;   to manage an Air Conditioning unit.
;
;   System Features & Requirements Met:
;   1. Temperature Sensing: Reads ambient temperature via LM35 (ADC) [R2.1.1-4].
;   2. User Interface: Accepts target temperature input via 4x4 Keypad [R2.1.2].
;   3. Feedback: Displays Temp, Target, and Fan Speed on 7-Segment Display [R2.1.3].
;   4. Control Logic: Actuates Heater (RB0) or Cooler (RB1) based on setpoint [R2.1.1-2/3].
;   5. Communication: UART Interface (9600 Baud) for PC synchronization [R2.1.4].
;
;   INTERRUPT STRUCTURE:
;   - UART RX (Priority): Handles asynchronous commands from PC.
;   - Timer1: Handles display multiplexing (~4ms refresh rate).
;******************************************************************************

    PROCESSOR 16F877A
    #include <xc.inc>

    ; --- CONFIGURATION BITS ---
    ; HS Oscillator (4MHz), Watchdog OFF, Power-up Timer ON, Low Voltage Prog OFF
    CONFIG FOSC = HS, WDTE = OFF, PWRTE = ON, BOREN = OFF, LVP = OFF, CPD = OFF, WRT = OFF, CP = OFF

;------------------------------------------------------------------------------
; VARIABLES (DATA MEMORY ALLOCATION)
;------------------------------------------------------------------------------
    PSECT udata_bank0
    
    ; --- Display & Timing Variables ---
    DISP_DIG1:      DS 1    ; Hundreds digit storage for multiplexing
    DISP_DIG2:      DS 1    ; Tens digit storage
    DISP_DIG3:      DS 1    ; Ones digit storage
    DISP_DIG4:      DS 1    ; Fourth digit (Unit/Symbol)
    DIGIT_SCAN_POS: DS 1    ; Active digit index (0-3) for scanning
    
    TMR1_COUNTER:   DS 1    ; Counter to derive 1-second interval from Timer1
    DISP_MODE:      DS 1    ; State variable for Display Mode (Ambient/Target/Fan)
    DISP_TIMER:     DS 1    ; Timer to toggle display mode every 2 seconds [R2.1.3-1]
    
    ; --- Keypad & Input State Machine Variables ---
    KEY_VAL:        DS 1    ; Decoded value of the pressed key
    KEY_PRESSED:    DS 1    ; Boolean flag: 1 = Key pressed, 0 = No press
    ENTRY_MODE:     DS 1    ; Flag: 1 = User is currently entering data [R2.1.2-1]
    INPUT_STEP:     DS 1    ; State pointer for data entry sequence (D1->D2->Dot->Frac)
    
    ; --- System Data [R2.1.1] ---
    ; Note: Temperatures are scaled (Value * 2) to handle 0.5 precision as integers.
    TARGET_ADC:     DS 1    ; Desired Temperature Setpoint [R2.1.1-1]
    CURRENT_ADC:    DS 1    ; Current Ambient Temperature (LM35) [R2.1.1-4]
    FAN_RPS:        DS 1    ; Fan Speed in Rotations Per Second [R2.1.1-5]
    
    ; --- Data Buffers ---
    INPUT_INT:      DS 1    ; Temporary storage for Integer part of input
    INPUT_FRAC:     DS 1    ; Temporary storage for Fractional part of input
    UART_RX_TEMP:   DS 1    ; Buffer for received UART byte
    PC_TARGET_INT:  DS 1    ; Received Target Integer from PC
    PC_TARGET_FRAC: DS 1    ; Received Target Fraction from PC
    
    ; --- General Purpose Helpers ---
    TEMP_CALC:      DS 1    ; General register for arithmetic operations
    TEMP_TX:        DS 1    ; Buffer for UART transmission
    D1:             DS 1    ; Delay loop counter 1
    D2:             DS 1    ; Delay loop counter 2
    SCAN_D:         DS 1    ; Debounce delay counter
    SEG_TEMP:       DS 1    ; Lookup table index holder

    ; --- Context Saving for ISR ---
    PSECT udata_shr
    W_ISR:          DS 1    ; W Register backup
    STATUS_ISR:     DS 1    ; STATUS Register backup

;==============================================================================
; RESET VECTOR & ISR (ABSOLUTE MODE CONFIGURATION)
;==============================================================================
    PSECT code, abs
    ORG 0x0000          ; Reset Vector
    GOTO    MAIN        ; Jump to Main Program

    ORG 0x0004          ; Interrupt Vector
    ; --- INTERRUPT SERVICE ROUTINE (ISR) ---
    ; Context Saving: Save critical registers before processing
    MOVWF   W_ISR
    SWAPF   STATUS, W
    MOVWF   STATUS_ISR
    
    BCF     STATUS, 5   ; Force Bank 0 for ISR operations
    BCF     STATUS, 6

    ; 1. UART RX Interrupt Handler [R2.1.4-1]
    ; Priority: High. Checks if a byte has been received from PC.
    BANKSEL PIR1
    BTFSC   PIR1, 5     ; Check RCIF (Receive Interrupt Flag)
    CALL    UART_RX_HANDLER

    ; 2. Timer1 Interrupt Handler (Display Refresh)
    ; Priority: Low. Used for 7-Segment Multiplexing.
    BANKSEL PIR1
    BTFSS   PIR1, 0     ; Check TMR1IF
    GOTO    EXIT_ISR    ; Exit if Timer1 did not overflow
    
    BCF     PIR1, 0     ; Clear TMR1 Interrupt Flag
    
    ; Reload Timer1 for approx 4ms interrupt interval
    ; Calculation: (65536 - 61536) * 1us = 4000us = 4ms
    MOVLW   0xF0
    MOVWF   TMR1H
    MOVLW   0x00
    MOVWF   TMR1L
    
    CALL    REFRESH_DISPLAY ; Update active digit
    
    ; 1 Second Timing Logic
    INCF    TMR1_COUNTER, F
    MOVF    TMR1_COUNTER, W
    SUBLW   250             ; 250 * 4ms = 1000ms = 1 Second
    BTFSS   STATUS, 0
    GOTO    TIMER_Tasks     ; Execute 1-second tasks
    GOTO    EXIT_ISR

TIMER_Tasks:
    CLRF    TMR1_COUNTER    ; Reset counter
    ; Task: Read Fan Speed [R2.1.1-5]
    ; TMR0 is configured as a counter for external pulses (Tachometer)
    MOVF    TMR0, W
    MOVWF   FAN_RPS
    CLRF    TMR0            ; Reset TMR0 for next accumulation
    
    ; Task: Rotate Display Mode [R2.1.3-1]
    INCF    DISP_TIMER, F
    BTFSS   DISP_TIMER, 1   ; Check if 2 seconds have passed
    GOTO    EXIT_ISR
    CLRF    DISP_TIMER
    INCF    DISP_MODE, F    ; Switch Mode (Ambient -> Target -> Fan)
    MOVF    DISP_MODE, W
    SUBLW   3
    BTFSC   STATUS, 2       ; Wrap around if Mode == 3
    CLRF    DISP_MODE
    
EXIT_ISR:
    ; Context Restore: Retrieve registers
    SWAPF   STATUS_ISR, W
    MOVWF   STATUS
    SWAPF   W_ISR, F
    SWAPF   W_ISR, W
    RETFIE

;==============================================================================
; UART SUBROUTINES (COMMUNICATION PROTOCOL)
; Protocol Implementation for [R2.1.4]
;==============================================================================
UART_RX_HANDLER:
    BANKSEL RCREG
    MOVF    RCREG, W        ; Read received data (Clears RCIF)
    BANKSEL UART_RX_TEMP
    MOVWF   UART_RX_TEMP
    
    ; Decode Command Byte
    
    ; GET Command: Desired Temp Fractional (0x01)
    MOVF    UART_RX_TEMP, W
    XORLW   0x01
    BTFSC   STATUS, 2
    GOTO    SEND_TARGET_FRAC

    ; GET Command: Desired Temp Integral (0x02)
    MOVF    UART_RX_TEMP, W
    XORLW   0x02
    BTFSC   STATUS, 2
    GOTO    SEND_TARGET_INT
    
    ; GET Command: Ambient Temp Fractional (0x03)
    MOVF    UART_RX_TEMP, W
    XORLW   0x03
    BTFSC   STATUS, 2
    GOTO    SEND_AMBIENT_FRAC
    
    ; GET Command: Ambient Temp Integral (0x04)
    MOVF    UART_RX_TEMP, W
    XORLW   0x04
    BTFSC   STATUS, 2
    GOTO    SEND_AMBIENT_INT
    
    ; GET Command: Fan Speed (0x05)
    MOVF    UART_RX_TEMP, W
    XORLW   0x05
    BTFSC   STATUS, 2
    GOTO    SEND_FAN_SPEED
    
    ; SET Command: Target Fractional (Format: 10xxxxxx)
    MOVF    UART_RX_TEMP, W
    ANDLW   0xC0            ; Mask upper 2 bits
    XORLW   0x80            ; Check if signature matches '10'
    BTFSC   STATUS, 2
    GOTO    SET_TARGET_FRAC
    
    ; SET Command: Target Integral (Format: 11xxxxxx)
    MOVF    UART_RX_TEMP, W
    ANDLW   0xC0
    XORLW   0xC0            ; Check if signature matches '11'
    BTFSC   STATUS, 2
    GOTO    SET_TARGET_INT
    
    ; Unknown command, exit handler
    GOTO    UART_RX_EXIT

;------------------------------------------------------------------------------
; SEND FUNCTIONS - Uses 'GOTO UART_RX_EXIT' for safe return from ISR
;------------------------------------------------------------------------------
SEND_TARGET_FRAC:
    MOVLW   0
    BTFSC   TARGET_ADC, 0   ; Check LSB (0.5 degree flag)
    MOVLW   5               ; If set, fractional part is 5
    CALL    SEND_TX_BYTE
    GOTO    UART_RX_EXIT

SEND_TARGET_INT:
    MOVF    TARGET_ADC, W
    MOVWF   TEMP_CALC
    BCF     STATUS, 0
    RRF     TEMP_CALC, F    ; Divide by 2 to get integer part
    MOVF    TEMP_CALC, W
    CALL    SEND_TX_BYTE
    GOTO    UART_RX_EXIT

SEND_AMBIENT_FRAC:
    MOVLW   0
    BTFSC   CURRENT_ADC, 0
    MOVLW   5
    CALL    SEND_TX_BYTE
    GOTO    UART_RX_EXIT

SEND_AMBIENT_INT:
    MOVF    CURRENT_ADC, W
    MOVWF   TEMP_CALC
    BCF     STATUS, 0
    RRF     TEMP_CALC, F
    MOVF    TEMP_CALC, W
    CALL    SEND_TX_BYTE
    GOTO    UART_RX_EXIT

SEND_FAN_SPEED:
    MOVF    FAN_RPS, W
    CALL    SEND_TX_BYTE
    GOTO    UART_RX_EXIT

;------------------------------------------------------------------------------
; SET FUNCTIONS (Handling Data Received from PC)
;------------------------------------------------------------------------------
SET_TARGET_FRAC:
    MOVF    UART_RX_TEMP, W
    ANDLW   0x3F            ; Extract lower 6 bits (data)
    MOVWF   PC_TARGET_FRAC
    GOTO    UART_RX_EXIT

SET_TARGET_INT:
    MOVF    UART_RX_TEMP, W
    ANDLW   0x3F            ; Extract lower 6 bits (data)
    MOVWF   PC_TARGET_INT
    GOTO    UPDATE_TARGET_FROM_PC

UPDATE_TARGET_FROM_PC:
    ; Reconstruct Full Target Value: (Integer * 2) + (Frac >= 5 ? 1 : 0)
    MOVF    PC_TARGET_INT, W
    MOVWF   TARGET_ADC
    BCF     STATUS, 0
    RLF     TARGET_ADC, F          ; Multiply by 2
    
    ; Rounding Logic: If fractional part >= 5, add 0.5C (increment bit 0)
    MOVF    PC_TARGET_FRAC, W
    SUBLW   4                      ; Check if Frac > 4
    BTFSS   STATUS, 0              
    INCF    TARGET_ADC, F          ; Add 0.5C
    GOTO    UART_RX_EXIT

;------------------------------------------------------------------------------
; TX BYTE TRANSMISSION ROUTINE
;------------------------------------------------------------------------------
SEND_TX_BYTE:
    MOVWF   TEMP_TX
    BANKSEL TXSTA
WAIT_TX:
    BTFSS   TXSTA, 1               ; Wait for TRMT (Transmit Shift Register Empty)
    GOTO    WAIT_TX
    BANKSEL TXREG
    MOVF    TEMP_TX, W
    MOVWF   TXREG                  ; Load data to transmit
    BANKSEL PORTB
    RETURN                         

;------------------------------------------------------------------------------
; UART EXIT POINT
;------------------------------------------------------------------------------
UART_RX_EXIT:
    RETURN                         ; Return to ISR
       
;==============================================================================
; MAIN PROGRAM (INITIALIZATION & LOOP)
;==============================================================================
MAIN:
    ; --- Bank 1 Initialization ---
    BSF     STATUS, 5
    CLRF    TRISD           ; PORTD Output (7-Segment Data)
    CLRF    TRISC           ; PORTC Output (7-Segment Control)
    MOVLW   0xF0
    MOVWF   TRISB           ; PORTB (Keypad Rows=Out, Cols=In)
    MOVLW   0x11
    MOVWF   TRISA           ; RA0 (ADC), RA4 (Timer0) as Inputs
    
    BCF     TRISC, 6        ; TX Pin (RC6) Output
    BSF     TRISC, 7        ; RX Pin (RC7) Input
    
    MOVLW   0x8E            ; ADCON1: AN0 Analog, Right Justified
    MOVWF   ADCON1
    MOVLW   0x28            ; OPTION_REG: TMR0 Counter Mode (RA4 Rising Edge)
    MOVWF   OPTION_REG
    
    ; UART Configuration: 9600 Baud @ 4MHz
    MOVLW   25              ; SPBRG = 25
    MOVWF   SPBRG
    BSF     TXSTA, 2        ; BRGH = 1 (High Speed)
    BCF     TXSTA, 4        ; SYNC = 0 (Asynchronous)
    BSF     TXSTA, 5        ; TXEN = 1 (Transmit Enable)
    
    BSF     PIE1, 0         ; Enable Timer1 Interrupt
    BSF     PIE1, 5         ; Enable UART RX Interrupt
    
    ; --- Bank 0 Initialization ---
    BCF     STATUS, 5
    BSF     RCSTA, 7        ; SPEN = 1 (Serial Port Enable)
    BSF     RCSTA, 4        ; CREN = 1 (Continuous Receive Enable)
    
    MOVLW   0x01            ; T1CON: 1:1 Prescaler, Timer1 On
    MOVWF   T1CON
    
    BSF     INTCON, 6       ; PEIE (Peripheral Interrupt Enable)
    BSF     INTCON, 7       ; GIE (Global Interrupt Enable)
    
    MOVLW   0x81            ; ADCON0: Fosc/32, Channel 0, ADC On
    MOVWF   ADCON0
    
    CLRF    PORTD
    CLRF    PORTC
    CLRF    PORTB
    
    ; Initialize Keypad Scanning Rows
    BSF     PORTA, 1
    BSF     PORTA, 2
    BSF     PORTA, 3
    BSF     PORTA, 5
    
    MOVLW   50              ; Initialize Default Target Temp: 25.0 C
    MOVWF   TARGET_ADC
    
    CLRF    ENTRY_MODE
    CLRF    KEY_PRESSED
    CLRF    DISP_MODE
    CLRF    TMR0

MAIN_LOOP:
    ; 1. Scan Keypad [R2.1.2]
    CALL    SCAN_KEYPAD
    MOVF    KEY_PRESSED, F
    BTFSS   STATUS, 2
    CALL    PROCESS_KEY
    
    ; 2. Input Blocking: If User is Typing, Skip Control Logic
    BTFSC   ENTRY_MODE, 0
    GOTO    SKIP_SYS
    
    ; 3. System Operations [R2.1.1]
    CALL    READ_SENSOR
    CALL    PREPARE_DISPLAY_DATA
    CALL    CONTROL_SYSTEM
    
SKIP_SYS:
    CALL    DELAY_MS        ; General System Delay
    CLRF    KEY_PRESSED     ; Reset Key Flag
    
    ; Debounce: Wait for Key Release
WAIT_UP:
    MOVF    PORTB, W
    ANDLW   0xF0
    XORLW   0xF0
    BTFSS   STATUS, 2
    GOTO    WAIT_UP
    GOTO    MAIN_LOOP

;==============================================================================
; SENSOR & DISPLAY ROUTINES
;==============================================================================
READ_SENSOR:
    BSF     ADCON0, 2       ; Start ADC Conversion
WAIT_ADC:
    BTFSC   ADCON0, 2       ; Poll GO/DONE bit
    GOTO    WAIT_ADC
    BANKSEL ADRESL
    MOVF    ADRESL, W
    BANKSEL PORTB
    MOVWF   CURRENT_ADC     ; Update Ambient Temp [R2.1.1-4]
    RETURN

PREPARE_DISPLAY_DATA:
    ; Multiplexing Logic: Select Data Source based on DISP_MODE
    MOVF    DISP_MODE, W
    SUBLW   0
    BTFSC   STATUS, 2
    GOTO    SHOW_AMBIENT
    MOVF    DISP_MODE, W
    SUBLW   1
    BTFSC   STATUS, 2
    GOTO    SHOW_TARGET
    GOTO    SHOW_FAN

SHOW_AMBIENT:
    MOVF    CURRENT_ADC, W
    CALL    CONVERT_TO_BCD
    MOVLW   0x3F            ; Segment '0'
    BTFSC   CURRENT_ADC, 0  ; Check 0.5 degree bit
    MOVLW   0x6D            ; Segment '5'
    MOVWF   DISP_DIG3
    MOVLW   0x39            ; Segment 'C' (Celsius)
    MOVWF   DISP_DIG4
    RETURN

SHOW_TARGET:
    MOVF    TARGET_ADC, W
    CALL    CONVERT_TO_BCD
    MOVLW   0x3F
    BTFSC   TARGET_ADC, 0
    MOVLW   0x6D
    MOVWF   DISP_DIG3
    MOVLW   0x5C            ; Segment for Degree Symbol
    MOVWF   DISP_DIG4
    RETURN

SHOW_FAN:
    MOVF    FAN_RPS, W
    MOVWF   TEMP_CALC
    ; Manual BCD Conversion (Hundreds, Tens, Ones) for Fan Speed
    CLRF    DISP_DIG1
    CLRF    DISP_DIG2
    CLRF    DISP_DIG3
CALC_100:
    MOVLW   100
    SUBWF   TEMP_CALC, W
    BTFSS   STATUS, 0
    GOTO    CALC_10
    MOVWF   TEMP_CALC
    INCF    DISP_DIG1, F
    GOTO    CALC_100
CALC_10:
    MOVLW   10
    SUBWF   TEMP_CALC, W
    BTFSS   STATUS, 0
    GOTO    CALC_1
    MOVWF   TEMP_CALC
    INCF    DISP_DIG2, F
    GOTO    CALC_10
CALC_1:
    MOVF    TEMP_CALC, W
    MOVWF   DISP_DIG3
    ; Map values to 7-Segment Codes
    MOVF    DISP_DIG1, W
    CALL    GET_SEG_MANUAL
    MOVWF   DISP_DIG1
    MOVF    DISP_DIG2, W
    CALL    GET_SEG_MANUAL
    MOVWF   DISP_DIG2
    MOVF    DISP_DIG3, W
    CALL    GET_SEG_MANUAL
    MOVWF   DISP_DIG3
    MOVLW   0x71            ; Segment 'F' (Fan)
    MOVWF   DISP_DIG4
    RETURN

CONVERT_TO_BCD:
    ; Converts (Value/2) to BCD for Display
    MOVWF   TEMP_CALC
    BCF     STATUS, 0
    RRF     TEMP_CALC, F    ; Integer division by 2
    CLRF    DISP_DIG1
    CLRF    DISP_DIG2
BCD_LOOP:
    MOVF    TEMP_CALC, W
    SUBLW   9
    BTFSC   STATUS, 0
    GOTO    BCD_END
    MOVLW   10
    SUBWF   TEMP_CALC, F
    INCF    DISP_DIG1, F
    GOTO    BCD_LOOP
BCD_END:
    MOVF    TEMP_CALC, W
    MOVWF   DISP_DIG2
    ; Map to Segments
    MOVF    DISP_DIG1, W
    CALL    GET_SEG_MANUAL
    MOVWF   DISP_DIG1
    MOVF    DISP_DIG2, W
    CALL    GET_SEG_MANUAL
    MOVWF   DISP_DIG2
    RETURN

CONTROL_SYSTEM:
    ; Hysteresis Logic [R2.1.1-2/3]
    MOVF    CURRENT_ADC, W
    SUBWF   TARGET_ADC, W
    BTFSC   STATUS, 2       ; If Target == Ambient
    GOTO    ALL_OFF         ; System Idle
    BTFSS   STATUS, 0       ; If Target < Ambient (Carry Clear)
    GOTO    COOL_ON         ; Activate Cooling
    GOTO    HEAT_ON         ; Activate Heating (Carry Set)
HEAT_ON:
    BCF     PORTB, 1
    BSF     PORTB, 0        ; Heater ON
    RETURN
COOL_ON:
    BCF     PORTB, 0
    BSF     PORTB, 1        ; Cooler ON
    RETURN
ALL_OFF:
    BCF     PORTB, 0
    BCF     PORTB, 1
    RETURN

;==============================================================================
; KEYPAD LOGIC (STATE MACHINE)
; Implements [R2.1.2] Data Entry Sequence
;==============================================================================
PROCESS_KEY:
    ; Check for Start Condition ('A' key) [R2.1.2-1]
    MOVF    KEY_VAL, W
    SUBLW   0x0A
    BTFSC   STATUS, 2
    GOTO    START_ENTRY
    
    BTFSS   ENTRY_MODE, 0   ; Ignore keys if not in Entry Mode
    RETURN
    
    ; State Machine Switch
    MOVF    INPUT_STEP, W
    SUBLW   0
    BTFSC   STATUS, 2
    GOTO    GET_D1          ; State 0: Get Tens Digit
    MOVF    INPUT_STEP, W
    SUBLW   1
    BTFSC   STATUS, 2
    GOTO    GET_D2          ; State 1: Get Units Digit
    MOVF    INPUT_STEP, W
    SUBLW   2
    BTFSC   STATUS, 2
    GOTO    GET_DOT         ; State 2: Get Dot/Star
    MOVF    INPUT_STEP, W
    SUBLW   3
    BTFSC   STATUS, 2
    GOTO    GET_FRAC        ; State 3: Get Fractional Part
    MOVF    INPUT_STEP, W
    SUBLW   4
    BTFSC   STATUS, 2
    GOTO    GET_CONFIRM     ; State 4: Confirm with '#'
    RETURN

START_ENTRY:
    BSF     ENTRY_MODE, 0
    CLRF    INPUT_STEP
    MOVLW   0x40            ; Display '-' indicating input mode
    MOVWF   DISP_DIG1
    MOVWF   DISP_DIG2
    MOVWF   DISP_DIG3
    MOVWF   DISP_DIG4
    CLRF    INPUT_INT
    CLRF    INPUT_FRAC
    RETURN

GET_D1:
    MOVF    KEY_VAL, W
    SUBLW   9
    BTFSS   STATUS, 0       ; Validate Numeric Input
    RETURN
    MOVF    KEY_VAL, W
    MOVWF   TEMP_CALC
    CLRF    INPUT_INT
    MOVLW   10
ADD10:                      ; Multiply Key by 10
    ADDWF   INPUT_INT, F
    DECFSZ  TEMP_CALC, F
    GOTO    ADD10
    MOVF    KEY_VAL, W
    CALL    GET_SEG_MANUAL
    MOVWF   DISP_DIG1
    INCF    INPUT_STEP, F
    RETURN

GET_D2:
    MOVF    KEY_VAL, W
    SUBLW   9
    BTFSS   STATUS, 0
    RETURN
    MOVF    KEY_VAL, W
    ADDWF   INPUT_INT, F    ; Add Units Digit
    MOVF    KEY_VAL, W
    CALL    GET_SEG_MANUAL
    MOVWF   DISP_DIG2
    INCF    INPUT_STEP, F
    RETURN

GET_DOT:
    MOVF    KEY_VAL, W
    SUBLW   0x0E            ; Check for '*' Key (acts as dot)
    BTFSS   STATUS, 2
    RETURN
    INCF    INPUT_STEP, F
    RETURN

GET_FRAC:
    MOVF    KEY_VAL, W
    SUBLW   9
    BTFSS   STATUS, 0
    RETURN
    MOVF    KEY_VAL, W
    MOVWF   INPUT_FRAC
    CALL    GET_SEG_MANUAL
    MOVWF   DISP_DIG3
    INCF    INPUT_STEP, F
    RETURN

GET_CONFIRM:
    MOVF    KEY_VAL, W
    SUBLW   0x0F            ; Check for '#' Key
    BTFSS   STATUS, 2
    RETURN
    
    ; Range Validation [R2.1.2-3]: 10.0 <= Input <= 50.0
    MOVLW   10
    SUBWF   INPUT_INT, W
    BTFSS   STATUS, 0       ; Fail if Input < 10
    GOTO    INVALID
    MOVF    INPUT_INT, W
    SUBLW   50
    BTFSS   STATUS, 0       ; Fail if Input > 50
    GOTO    INVALID
    
    ; Specific check for 50.0 (Fraction must be 0)
    MOVF    INPUT_INT, W
    XORLW   50
    BTFSS   STATUS, 2
    GOTO    SAVE_VAL
    MOVF    INPUT_FRAC, W
    SUBLW   0
    BTFSS   STATUS, 2
    GOTO    INVALID

SAVE_VAL:
    ; Store Validated Data [R2.1.2-4]
    MOVF    INPUT_INT, W
    MOVWF   TARGET_ADC
    BCF     STATUS, 0
    RLF     TARGET_ADC, F   ; Scale x2
    MOVF    INPUT_FRAC, W
    SUBLW   4               ; Rounding Logic
    BTFSS   STATUS, 0
    INCF    TARGET_ADC, F
    CLRF    ENTRY_MODE
    RETURN

INVALID:
    CLRF    ENTRY_MODE      ; Abort Entry
    RETURN

;==============================================================================
; LOW LEVEL DRIVERS (KEYPAD SCAN & DISPLAY LOOKUP)
;==============================================================================
SCAN_KEYPAD:
    ; Matrix Scan Logic
    CLRF KEY_VAL
    CLRF KEY_PRESSED
    
    ; Row 1 Scan
    BSF PORTA,1
    BSF PORTA,2
    BSF PORTA,3
    BSF PORTA,5
    CALL D_SC
    BCF PORTA,1
    CALL D_SC
    BTFSS PORTB,4
    GOTO K1
    BTFSS PORTB,5
    GOTO K2
    BTFSS PORTB,6
    GOTO K3
    BTFSS PORTB,7
    GOTO KA
    
    ; Row 2 Scan
    BSF PORTA,1
    CALL D_SC
    BCF PORTA,2
    CALL D_SC
    BTFSS PORTB,4
    GOTO K4
    BTFSS PORTB,5
    GOTO K5
    BTFSS PORTB,6
    GOTO K6
    BTFSS PORTB,7
    GOTO KB
    
    ; Row 3 Scan
    BSF PORTA,2
    CALL D_SC
    BCF PORTA,3
    CALL D_SC
    BTFSS PORTB,4
    GOTO K7
    BTFSS PORTB,5
    GOTO K8
    BTFSS PORTB,6
    GOTO K9
    BTFSS PORTB,7
    GOTO KC
    
    ; Row 4 Scan
    BSF PORTA,3
    CALL D_SC
    BCF PORTA,5
    CALL D_SC
    BTFSS PORTB,4
    GOTO KS
    BTFSS PORTB,5
    GOTO K0
    BTFSS PORTB,6
    GOTO KH
    BTFSS PORTB,7
    GOTO KD
    BSF PORTA,5
    RETURN
    
    ; Key Mapping Table
K1: MOVLW 1
    GOTO FND
K2: MOVLW 2
    GOTO FND
K3: MOVLW 3
    GOTO FND
KA: MOVLW 0x0A
    GOTO FND
K4: MOVLW 4
    GOTO FND
K5: MOVLW 5
    GOTO FND
K6: MOVLW 6
    GOTO FND
KB: MOVLW 0x0B
    GOTO FND
K7: MOVLW 7
    GOTO FND
K8: MOVLW 8
    GOTO FND
K9: MOVLW 9
    GOTO FND
KC: MOVLW 0x0C
    GOTO FND
KS: MOVLW 0x0E ; * Star
    GOTO FND
K0: MOVLW 0
    GOTO FND
KH: MOVLW 0x0F ; # Hash
    GOTO FND
KD: MOVLW 0x0D
    GOTO FND
FND: MOVWF KEY_VAL
     BSF KEY_PRESSED,0
     RETURN

REFRESH_DISPLAY:
    CLRF PORTC              ; Blank Display
    INCF DIGIT_SCAN_POS,F   ; Move to next digit
    MOVF DIGIT_SCAN_POS,W
    ANDLW 0x03              ; Wrap 0-3
    MOVWF DIGIT_SCAN_POS
    
    ; Digit Select Logic
    MOVF DIGIT_SCAN_POS,W
    SUBLW 0
    BTFSC STATUS,2
    GOTO D1_ON
    MOVF DIGIT_SCAN_POS,W
    SUBLW 1
    BTFSC STATUS,2
    GOTO D2_ON
    MOVF DIGIT_SCAN_POS,W
    SUBLW 2
    BTFSC STATUS,2
    GOTO D3_ON
    GOTO D4_ON
D1_ON:
    MOVF DISP_DIG1,W
    MOVWF PORTD
    BSF PORTC,0
    RETURN
D2_ON:
    MOVF DISP_DIG2,W
    BTFSC DISP_MODE, 1      ; Check if Dot is needed (Target Mode)
    GOTO  SEND_D2        
    IORLW 0x80              ; Add Dot Point
SEND_D2:
    MOVWF PORTD
    BSF PORTC,1
    RETURN
D3_ON:
    MOVF DISP_DIG3,W
    MOVWF PORTD
    BSF PORTC,2
    RETURN
D4_ON:
    MOVF DISP_DIG4,W
    MOVWF PORTD
    BSF PORTC,3
    RETURN

GET_SEG_MANUAL:
    ; 7-Segment Look-up Table (Common Cathode)
    MOVWF SEG_TEMP
    MOVF SEG_TEMP,W
    XORLW 0
    BTFSC STATUS,2
    RETLW 0x3F      ; 0
    MOVF SEG_TEMP,W
    XORLW 1
    BTFSC STATUS,2
    RETLW 0x06      ; 1
    MOVF SEG_TEMP,W
    XORLW 2
    BTFSC STATUS,2
    RETLW 0x5B      ; 2
    MOVF SEG_TEMP,W
    XORLW 3
    BTFSC STATUS,2
    RETLW 0x4F      ; 3
    MOVF SEG_TEMP,W
    XORLW 4
    BTFSC STATUS,2
    RETLW 0x66      ; 4
    MOVF SEG_TEMP,W
    XORLW 5
    BTFSC STATUS,2
    RETLW 0x6D      ; 5
    MOVF SEG_TEMP,W
    XORLW 6
    BTFSC STATUS,2
    RETLW 0x7D      ; 6
    MOVF SEG_TEMP,W
    XORLW 7
    BTFSC STATUS,2
    RETLW 0x07      ; 7
    MOVF SEG_TEMP,W
    XORLW 8
    BTFSC STATUS,2
    RETLW 0x7F      ; 8
    MOVF SEG_TEMP,W
    XORLW 9
    BTFSC STATUS,2
    RETLW 0x6F      ; 9
    RETLW 0x40      ; Default Dash

DELAY_MS:
    ; Simple nested loop delay
    MOVLW 250
    MOVWF D1
DL1: MOVLW 250
    MOVWF D2
DL2: DECFSZ D2,F
    GOTO DL2
    DECFSZ D1,F
    GOTO DL1
    RETURN

D_SC:
    ; Keypad scan stabilization delay
    MOVLW 100
    MOVWF SCAN_D
    NOP
    DECFSZ SCAN_D,F
    GOTO $-2
    RETURN

    END