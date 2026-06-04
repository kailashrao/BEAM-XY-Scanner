# trigger_viper_optimized.py
# Updated 6/3/2026 by Kailash Rao

# Generate trigger after TRIGGER_EVERY rising edges from encoder

# CPU interrupts
# Using micropython.viper handlers for lower latency and zero-allocation jitter

import gc
from machine import Pin
import time
import sys
import select
from array import array

# --- RP2040 Hardware SIO Register Offsets ---
SIO_BASE     = 0xd0000000
GPIO_IN      = 1  # Offset 0x004 // 4 (Read input pins)
GPIO_OUT_SET = 5  # Offset 0x014 // 4 (Atomic set outputs HIGH)
GPIO_OUT_CLR = 6  # Offset 0x018 // 4 (Atomic clear outputs LOW)

GP20_MASK    = 0x100000  # Bit 20 (Trigger Output)
GP21_MASK    = 0x200000  # Bit 21 (Encoder Input)

# Pre-allocate an array to hold state variables. 
# Bypasses Python global variable dictionary lookups inside the interrupt.
# Index 0 = pulse_count, Index 1 = firing_state
state = array('i', [0, 0])

# Configure hardware multiplexing and pull-down configurations
input_pin = Pin(21, Pin.IN, Pin.PULL_DOWN)
trigger_pin = Pin(20, Pin.OUT)
trigger_pin.value(0)

@micropython.viper
def fast_pulse_handler(pin_obj):
    # Cast variables to raw 32-bit pointers
    st = ptr32(state)
    sio = ptr32(SIO_BASE)
    
    # 1. Read the raw SIO Input Register directly (Bypasses pin_obj.value() wrapper)
    if sio[1] & 0x200000:  
        # --- RISING EDGE DETECTED ---
        st[0] += 1         # Increment pulse_count
        
        # 2. Optimized Reset instead of Modulo Division
        if st[0] == 5:     
            sio[5] = 0x100000  # Blast GP20 HIGH instantly via single-cycle atomic SET register
            st[0] = 0          # Reset counter
            st[1] = 1          # Set firing state to active
    else:
        # --- FALLING EDGE DETECTED ---
        if st[1] == 1:
            sio[6] = 0x100000  # Blast GP20 LOW instantly via atomic CLEAR register
            st[1] = 0          # Reset firing state

# --- CRITICAL FOR JITTER ELIMINATION ---
# Completely disable automatic background Garbage Collection.
# Bypasses unexpected multi-millisecond pauses during tracking loops.
gc.disable()

# Register the consolidated hardware interrupt hook
input_pin.irq(trigger=Pin.IRQ_RISING | Pin.IRQ_FALLING, handler=fast_pulse_handler, hard=True)

print("Running with VIPER hardware extensions. Press 'q' + Enter to stop.")

try:
    while True:
        # Check for user termination without creating new heap strings
        if select.select([sys.stdin], [], [], 0)[0]:
            key = sys.stdin.read(1)
            if key == 'q':
                break
        
        # REMOVED continuous print formatting statement. 
        # Guarantees 0% heap allocation churn while the motor is spinning.
        time.sleep_ms(200)

except KeyboardInterrupt:
    pass

# --- Clean up and restore safe state ---
input_pin.irq(handler=None)
trigger_pin.value(0)
gc.enable()  # Re-enable GC for standard system operations
print("\nExecution Halting. Tracking system disarmed.")