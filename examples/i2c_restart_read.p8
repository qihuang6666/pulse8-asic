; Single-controller combined transaction: address 0x50 W, repeated START,
; address 0x50 R, one-byte read, controller NACK, STOP. No register pointer.
; GPIO0=SDA, GPIO1=SCL. Set open-drain mask=3 and use external pull-ups.
; Waits for SCL on EVERY high phase, including ACK/NACK/START/STOP.
; This current-address read example needs a target that accepts an empty write.
PINS 3, 3
WAIT 1, 1 [4095]
WAIT 0, 1 [4095]
MASK 0, 1 [119]
MASK 0, 2 [119]
SET 0xa0
SETX 8
write_address:
OUT 0, 1 [119]
MASK 2, 2
WAIT 1, 1 [4095]
NOP [119]
MASK 0, 2 [117]
DJNZ write_address
MASK 1, 1 [119]
MASK 2, 2
WAIT 1, 1 [4095]
NOP [119]
WAIT 0, 0 [1]
MASK 0, 2 [119]
MASK 1, 1 [119]
MASK 2, 2
WAIT 1, 1 [4095]
NOP [119]
MASK 0, 1 [119] ; repeated START, no intervening STOP
MASK 0, 2 [119]
SET 0xa1
SETX 8
read_address:
OUT 0, 1 [119]
MASK 2, 2
WAIT 1, 1 [4095]
NOP [119]
MASK 0, 2 [117]
DJNZ read_address
MASK 1, 1 [119]
MASK 2, 2
WAIT 1, 1 [4095]
NOP [119]
WAIT 0, 0 [1]
MASK 0, 2 [119]
SETX 8
MASK 1, 1 [119]
read_bit:
MASK 2, 2
WAIT 1, 1 [4095]
NOP [59]
IN 0, 1 [59]
MASK 0, 2 [118]
DJNZ read_bit
MASK 2, 2 ; ninth clock with SDA released = controller NACK
WAIT 1, 1 [4095]
NOP [119]
MASK 0, 3 [119]
MASK 2, 2
WAIT 1, 1 [4095]
NOP [119]
MASK 1, 1 [119] ; STOP
PUSH 1
HALT
