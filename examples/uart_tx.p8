; GPIO0: TX, 8N1, 24 MHz / 208 = 115384.6 baud.
; Preload one byte with host command 0x04 before START.
PINS 1, 1
PULL
SETX 8
PINS 0, 1 [207]
bits:
OUT 0, 0 [206]
DJNZ bits
PINS 1, 1 [207]
HALT
