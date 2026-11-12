; Single-controller I2C write: address 0x50, one host-provided byte.
; GPIO0=SDA, GPIO1=SCL. Set host open-drain mask=3; add external pull-ups.
; About 100 kHz at 24 MHz; each released SCL is checked for clock stretching.
; Both ACKs are checked with bounded WAIT. NACK/overlong stretch safely faults.
PINS 3, 3
WAIT 1, 1 [4095]
WAIT 0, 1 [4095]
MASK 0, 1 [119] ; START
MASK 0, 2 [119]
SET 0xa0
SETX 8
address_bit:
OUT 0, 1 [59]
MASK 2, 2
WAIT 1, 1 [4095]
NOP [119]
MASK 0, 2 [57]
DJNZ address_bit
MASK 1, 1 [59] ; release SDA for address ACK
MASK 2, 2
WAIT 1, 1 [4095]
NOP [59]
WAIT 0, 0 [1]
NOP [59]
MASK 0, 2 [119]
PULL
SETX 8
data_bit:
OUT 0, 1 [59]
MASK 2, 2
WAIT 1, 1 [4095]
NOP [119]
MASK 0, 2 [57]
DJNZ data_bit
MASK 1, 1 [59]
MASK 2, 2
WAIT 1, 1 [4095]
NOP [59]
WAIT 0, 0 [1]
NOP [59]
MASK 0, 2 [119]
MASK 0, 1 [119]
MASK 2, 2
WAIT 1, 1 [4095]
NOP [119]
MASK 1, 1 [119] ; STOP
SET 0
PUSH 0 ; success token
HALT
