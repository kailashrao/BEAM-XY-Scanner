# trigger_pio.py
# Updated 6/3/2026 by Kailash Rao

# Generate trigger after TRIGGER_EVERY rising edges from encoder

# Uses PIO state machine for hardware-based pulse-width matching (lowest latency, zero CPU load)

import rp2
from machine import Pin
import time

# ==========================================
# 1. PIO ENGINE (PULSE-WIDTH MATCHING)
# ==========================================
@rp2.asm_pio(set_init=rp2.PIO.OUT_LOW)
def encoder_divider_mirror():
    wrap_target()
    
    # ---- Phase 1: Count and discard 4 encoder pulses ----
    set(x, 3)                 # Loop 4 times (pulses 1, 2, 3, 4)
    label("pulse_loop")
    wait(1, pin, 0)           # Wait for rising edge
    wait(0, pin, 0)           # Wait for falling edge
    jmp(x_dec, "pulse_loop")  
    
    # ---- Phase 2: Mirror the 5th Pulse Length ----
    wait(1, pin, 0)           # 5th Rising Edge occurs!
    set(pins, 1)              # Drive GP20 HIGH immediately
    
    wait(0, pin, 0)           # Wait right here for the 5th pulse to physically fall
    set(pins, 0)              # Drive GP20 LOW immediately when the input drops
    
    wrap()

# ==========================================
# 2. HARDWARE SETUP
# ==========================================
# Input: Encoder signal on GP21 (Using PULL_DOWN or PULL_UP depending on your setup)
encoder_pin = Pin(2, Pin.IN, Pin.PULL_DOWN)

# Output: Radar Trigger on GP20
trigger_pin = Pin(21, Pin.OUT, value=0)

# Instantiate State Machine 0 at 2 MHz
sm = rp2.StateMachine(
    0, 
    encoder_divider_mirror, 
    freq=2000000, 
    in_base=encoder_pin,   # Input pin 0 = GP21
    set_base=trigger_pin   # Output pin 0 = GP20
)

# Activate the hardware gates
sm.active(1)

print("==========================================================")
print("PIO Pulse-Width Matching Trigger Engine Online!")
print("Output GP20 duration will perfectly mirror input GP21.")
print("==========================================================")

# ==========================================
# 3. LIVE SCOPE DIAGNOSTIC
# ==========================================
pulse_count = 0
last_state = encoder_pin.value()

while True:
    current_state = encoder_pin.value()
    if current_state == 1 and last_state == 0:
        pulse_count += 1
    last_state = current_state
    
    print(f"[Diagnostic] Total Pulses Counted: {pulse_count}", end="\r")
    time.sleep(0.01)