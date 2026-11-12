; SPI controller mode 3, MSB-first, 100 kHz at 24 MHz.
; GPIO0=SCK, GPIO1=MOSI, GPIO2=MISO, GPIO3=CS_n.
; Preload TX with command 0x04. RX is returned via PUSH 1.
PINS 9, 11
PULL
SETX 8
MASK 0, 8 [119]
bit:
MASK 0, 1
OUT 1, 1 [118]
MASK 1, 1 [117]
IN 2, 1
DJNZ bit
MASK 8, 8
PUSH 1
HALT
