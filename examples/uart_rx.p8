; GPIO0: RX, 8N1. External source must idle high before START.
; 208 clocks/bit. One byte per invocation; resubmit START after reading RX.
PINS 0, 0
SETX 8
WAIT 0, 0
NOP [310]
bits:
IN 0, 0 [206]
DJNZ bits
WAIT 0, 1 [1] ; stop-bit check; a low stop bit produces WAIT timeout
PUSH 1
HALT
