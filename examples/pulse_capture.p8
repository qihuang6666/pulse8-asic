; Launch a test stimulus, classify the DUT response, and return its elapsed time.
; GPIO0: response input, GPIO1: active-high trigger output.
; GPIO2: qualifier input (held stable around response), GPIO3: classification output.
; Host receives low timestamp byte then high byte. Clock: 24 MHz intended.
; Both qualifier paths take equal time and run before either host PUSH can stall.
PINS 0, 10
WAIT 0, 0 [4095]       ; establish response idle, or fault safely
TRESET
MASK 2, 2              ; launch one edge after the timer reference
WAIT 0, 1 [4095]       ; observe the synchronized DUT response
SAMPLE 4
JNZ qualified
MASK 0, 8
JMP capture
qualified: MASK 8, 8 [1] ; equalize the two branch paths
capture: TSTAMP
MASK 0, 2              ; release trigger; hold classification until restart/STOP
PUSH 0
PUSH 1
HALT
