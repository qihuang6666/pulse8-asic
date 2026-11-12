; One-byte register read: address0x50 W, host-provided register pointer,
; repeated START, address0x50 R, one received byte, controller NACK, STOP.
; GPIO0=SDA, GPIO1=SCL; host open-drain mask=3, external pull-ups.
; This compact example does NOT support clock stretching or arbitration.
; ACKs are checked. Use i2c_restart_read for a stretch-capable current read.
PINS 3, 3 [119]
MASK 0, 1 [119]
MASK 0, 2 [119]
SET 0xa0
SETX 8
address_write:
OUT 0, 1 [119]
MASK 2, 2 [119]
MASK 0, 2 [117]
DJNZ address_write
MASK 1, 1 [119]
MASK 2, 2 [119]
WAIT 0, 0 [1]
MASK 0, 2 [119]
PULL
SETX 8
register:
OUT 0, 1 [119]
MASK 2, 2 [119]
MASK 0, 2 [117]
DJNZ register
MASK 1, 1 [119]
MASK 2, 2 [119]
WAIT 0, 0 [1]
MASK 0, 2 [119]
MASK 1, 1 [119]
MASK 2, 2 [119]
MASK 0, 1 [119]
MASK 0, 2 [119]
SET 0xa1
SETX 8
address_read:
OUT 0, 1 [119]
MASK 2, 2 [119]
MASK 0, 2 [117]
DJNZ address_read
MASK 1, 1 [119]
MASK 2, 2 [119]
WAIT 0, 0 [1]
MASK 0, 2 [119]
SETX 8
MASK 1, 1 [119]
read_bit:
MASK 2, 2 [59]
IN 0, 1 [59]
MASK 0, 2 [118]
DJNZ read_bit
MASK 2, 2 [119] ; released SDA gives controller NACK
MASK 0, 3 [119]
MASK 2, 2 [119]
MASK 1, 1 [119] ; STOP
PUSH 1
HALT
