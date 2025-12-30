;===========================================================
; PROJECT: CURTAIN CONTROL SYSTEM (LDR ONLY)
; MICROPROCESSOR: PIC16F877A
; COMLIPER: XC8 (PIC-AS) compatible
; STUDENT: TUĞBERK İNANIR
; ID: 151220202029
; DATE: December 2025
; DESCRIPTION: 
;   This program adjusts the stepper motor based on whether 
;   the analog value read from a light-dependent resistor is
;   above or below a specific threshold. If it is above the 
;   threshold, it does nothing, but if it is below the 
;   threshold, it activates the step motor to close the 
;   curtain to 100%.    
;===========================================================

    PROCESSOR 16F877A
    #include <xc.inc>

    ; CONFIG OPTIONS
    CONFIG FOSC = HS        ; High Speed Oscillator
    CONFIG WDTE = OFF       ; Watchdog Timer Disabled
    CONFIG PWRTE = ON       ; Power-up Timer Enabled
    CONFIG BOREN = ON       ; Brown-out Reset Enabled
    CONFIG LVP = OFF        ; Low Voltage Programming Disabled
    CONFIG CPD = OFF        ; Data EEPROM Code Protection OFF
    CONFIG WRT = OFF        ; Flash Write Protection OFF
    CONFIG CP = OFF         ; Flash Code Protection OFF

    ;-----------------------------------------------------------
    ; VARIABLES
    ;-----------------------------------------------------------
    ; Bank 0 RAM (0x20 - 0x7F)
    
CURRENT_POS     EQU     0x20    ; Mevcut Konum (%)
TARGET_POS      EQU     0x21    ; Hedef Konum (%)
D1              EQU     0x3A    ; Gecikme 1
LDR_VAL         EQU     0x3C    ; LDR ADC Value
W_ISR           EQU     0x70    ; Kesme için W kayd? yede?i (Shared RAM)
STATUS_ISR      EQU     0x71    ; Kesme için STATUS yede?i

; LDR Threshold Value
LDR_THRESHOLD   EQU     87      ; 1.7V * 255 / 5V = 87

    ;-----------------------------------------------------------
    ; START
    ;-----------------------------------------------------------
    PSECT code, abs
    ORG 0x00
    GOTO MAIN		    ; The program goes to the MAIN.
    
    ORG 0x04		    ; --- INTERRUPT SERVICE ROUTINE ---
ISR:
    MOVWF   W_ISR	    ; Backup W_ISR
    SWAPF   STATUS, W	    ; Swap nibbles of STATUS and store in working register
    MOVWF   STATUS_ISR	    ; Backup STATUS_ISR
    BCF     STATUS, 5	    ; Switch Bank 0


EXIT_ISR:
    SWAPF   STATUS_ISR, W   ; Swap nibbles of STATUS and store in working register
    MOVWF   STATUS	    ; Reload STATUS
    SWAPF   W_ISR, F	    ; Swap nibbles of W_ISR and store in file register W_ISR
    SWAPF   W_ISR, W	    ; Reload W_ISR
    RETFIE		    ; Return from interrupt

;===========================================================
; MAIN PROGRAM
;===========================================================
MAIN:
    ; --- ADC Options ---
    BANKSEL ADCON0	; 0000 0001 = 0x01 => A/D converter module is operating.
    MOVLW   0x41        ; 0001 0001 = 0x41 => A/D conversion clock Fosc/8 is selected.
    MOVWF   ADCON0	; Fosc/8, Channel 0, ADC ON

    ; --- Interrupt Enable ---
    BANKSEL PIE1
    BSF     PIE1, 5     ; RCIE = 1 (Receive Interrupt Enable)
    BSF     INTCON, 7   ; GIE = 1 (Global Interrupt Enable)
    BSF     INTCON, 6   ; PEIE = 1 (Peripheral Interrupt Enable)
    
    ; --- Clear Variables ---
    BANKSEL CURRENT_POS ; The program goes to the bank where CURRENT_POS is located.
    CLRF    CURRENT_POS ; CURRENT_POS is cleared.
    CLRF    TARGET_POS  ; TARGET_POS is cleared.

LOOP:
    ; --- LDR Control ---
    CALL    Light_Dependent_Resistor   ; Calls Light_Dependent_Resistor subroutine
    GOTO    LOOP                       ; The program goes to LOOP

;===========================================================
; LDR SENSOR READING AND LOGIC
;===========================================================
Light_Dependent_Resistor:
    BANKSEL ADCON0	    ; 0000 0001 = 0x01 => A/D converter module is operating.
    MOVLW   0x49            ; 0000 1001 = 0x09 => Analog channel 1 is selected.
    MOVWF   ADCON0	    ; 0001 1001 = 0x49 => A/D conversion clock Fosc/8 is selected.
    
    MOVLW   5		    ; Waiting for channel select...
    MOVWF   D1		    ; The value 5 was assigned to the D1 variable.
LDR_Acq:
    DECFSZ  D1, F	    ; If the D1 variable is greater than 0, the D1 value decreases by 1 and the cycle enters the LDR_Acq loop.
    GOTO    LDR_Acq	    ; If the D1 variable is 0, the LDR_Acq loop is skipped. 

    BANKSEL ADCON0	    ; The program goes to the bank where ADCON0 is located.
    BSF     ADCON0, 2       ; A/D conversion is started
Wait_LDR:
    BTFSC   ADCON0, 2	    ; Waiting for A/D conversion...
    GOTO    Wait_LDR	    ; Until A/D Conversion status bit is set.

    MOVF    ADRESH, W       ; A/D result high register moved to the working register.
    SUBLW   250             ; W = 250 - ADRESH.	 Mathematical calculations were performed to ensure that the LDR value showed higher results at higher values.
    BTFSS   STATUS, 0       ; If the ADRESH is greater than 250 (ADRESH > 250),
    MOVLW   0               ; The value is set to 0 and the value is defined in the LDR_VAL variable.
    MOVWF   LDR_VAL         ; Else, the subtraction between 250 and ADRESH is defined in the LDR_VAL variable.

    MOVLW   LDR_THRESHOLD   ; The threshold value, which defined as 87, is assigned to the working register.
    SUBWF   LDR_VAL, W      ; The subtraction between the LDR_VAL and LDR_THRESHOLD variables is calculated and the result value is defined in the working register.
    BTFSS   STATUS, 0       ; If the LDR_VAL value is below LDR_THRESHOLD value,
    GOTO    Close_Curtain   ; The program goes to the Close_Curtain subroutine first and then the program goes to the LDR_Cleanup subroutine.
    GOTO    LDR_Cleanup	    ; Else, the program bypasses the Close_Curtain subroutine and the program goes directly to the LDR_Cleanup subroutine.
    RETURN		    ; The program returns to Loop from the Light_Dependent_Resistor subroutine.

Close_Curtain:
    MOVLW   100		    ; The value 100 was assigned to the TARGET_POS variable.
    MOVWF   TARGET_POS	    ; When the TARGET_POS value is defined to 100, the stepp motor closes the curtain at 100%.
    RETURN		    ; The program returns to Light_Dependent_Resistor from the Close_Curtain subroutine.
    
LDR_Cleanup:
    BANKSEL ADCON0	    ; The program goes to the bank where ADCON0 is located.
    MOVLW   0x41	    ; 0001 0001 = 0x41 => Analog channel 0 is selected.
    MOVWF   ADCON0	    ; The value in working register is assinged to the ADCON0 file register.
    RETURN		    ; The program returns to Light_Dependent_Resistor from the LDR_Cleanup subroutine.
    
    END			    ; END
