; JTAG TAP reset, 4-bit IR=2, and 8-bit DR scan, LSB-first.
; About 100kHz inside shift loops at 24MHz; TAP navigation has longer gaps.
; GPIO0=TCK, GPIO1=TMS, GPIO2=TDI, GPIO3=TDO. No TRST required.
; Preload host TX with scan data; PUSH1 returns the captured target byte.
; Target-specific contract: 4-bit IR instruction2 selects an 8-bit DR.
; Change IR width/instruction and DR width for the actual target device.
PINS 2, 7 [119]
SETX 5
reset_clock:
MASK 1, 1 [119]
MASK 0, 1 [118]
DJNZ reset_clock
MASK 0, 2 [119] ; Test-Logic-Reset -> Run-Test/Idle
MASK 1, 1 [119]
MASK 0, 1 [119]
MASK 2, 2 [119] ; -> Select-DR-Scan (navigate to IR)
MASK 1, 1 [119]
MASK 0, 1 [119]
MASK 1, 1 [119] ; -> Select-IR-Scan
MASK 0, 1 [119]
MASK 0, 2 [119] ; -> Capture-IR
MASK 1, 1 [119]
MASK 0, 1 [119]
MASK 1, 1 [119] ; -> Shift-IR
MASK 0, 1 [119]
SET 2
SETX 3
instruction_bit:
OUT 2, 0 [117]
MASK 1, 1 [119]
MASK 0, 1
DJNZ instruction_bit
OUT 2, 0 [117]
MASK 2, 2
MASK 1, 1 [119] ; final IR bit -> Exit1-IR
MASK 0, 1 [119]
MASK 1, 1 [119] ; -> Update-IR
MASK 0, 1 [119]
MASK 0, 2 [119]
MASK 1, 1 [119] ; -> Run-Test/Idle
MASK 0, 1 [119]
MASK 2, 2 [119] ; -> Select-DR-Scan
MASK 1, 1 [119]
MASK 0, 1 [119]
MASK 0, 2 [119] ; -> Capture-DR
MASK 1, 1 [119]
MASK 0, 1 [119]
MASK 1, 1 [119] ; -> Shift-DR
MASK 0, 1 [119]
PULL
SETX 7
scan_bit:
OUT 2, 0 [117]
MASK 1, 1 [59]
IN 3, 0 [59]
MASK 0, 1
DJNZ scan_bit
OUT 2, 0 [117]
MASK 2, 2 ; final scan bit exits Shift-DR
MASK 1, 1 [59]
IN 3, 0 [59]
MASK 0, 1 [119]
MASK 1, 1 [119] ; Exit1-DR -> Update-DR
MASK 0, 1 [119]
MASK 0, 2 [119]
MASK 1, 1 [119] ; Update-DR -> Run-Test/Idle
MASK 0, 1
PUSH 1
HALT
