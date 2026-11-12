; Deliberate UART framing-error stimulus for testing a receiver's recovery.
; GPIO0=TX, 208 clocks/bit at24MHz. Preload host TX byte before START.
; Emits START +8LSB-first data bits +one LOW stop bit, then returns idle HIGH.
; This is intentionally invalid8N1, not a conforming UART transmitter.
PINS 1, 1
PULL
SETX 8
PINS 0, 1 [207]
bits:
OUT 0, 0 [206]
DJNZ bits
PINS 0, 1 [207] ; programmed fault: invalid stop bit
PINS 1, 1 [207] ; explicit idle recovery interval
HALT
