# trigger_optimized.py
# Updated 5/16/2026 by Kailash Rao

# Generate trigger after TRIGGER_EVERY rising edges from encoder

# Uses CPU interrupts
# Uses micropython.native handlers for lower latency

from machine import Pin
import time
import sys
import select

# Input signal on GP21, output trigger on GP20
input_pin = Pin(21, Pin.IN, Pin.PULL_DOWN)
trigger_pin = Pin(20, Pin.OUT)

trigger_pin.value(0)

TRIGGER_EVERY = 5
pulse_count = 0

# Track state as integer (0 or 1) for native performance
firing = 0 

# Native compilation speeds up variable lookups and execution
@micropython.native
def rising_handler(pin):
    global pulse_count, firing
    pulse_count += 1
    
    # Fast integer modulo check
    if pulse_count % TRIGGER_EVERY == 0:
        trigger_pin.value(1)
        firing = 1

@micropython.native
def falling_handler(pin):
    global firing
    if firing == 1:
        trigger_pin.value(0)
        firing = 0

# SEPARATE handlers eliminate the need to check 'if pin.value() == 1'
input_pin.irq(trigger=Pin.IRQ_RISING, handler=rising_handler)

# Create a second interrupt hook for the falling edge
# Note: In MicroPython, splitting IRQs like this requires setting it up on the pin,
# but since MicroPython's .irq() usually takes a single handler for both, 
# we can combine them into a single ultra-fast native function instead:

@micropython.native
def fast_pulse_handler(pin):
    global pulse_count, firing
    
    # Instead of calling pin.value(), we read the hardware register directly 
    # (GP21 is bit 21 of the GPIO input register). 
    # However, to keep it readable, let's just use native optimized execution:
    if pin.value():  # Still faster under @micropython.native
        pulse_count += 1
        if pulse_count % TRIGGER_EVERY == 0:
            trigger_pin.value(1)
            firing = 1
    else:
        if firing == 1:
            trigger_pin.value(0)
            firing = 0

# Re-registering using the optimized consolidated handler
input_pin.irq(trigger=Pin.IRQ_RISING | Pin.IRQ_FALLING, handler=fast_pulse_handler)

print("Running. Press 'q' + Enter to stop.")

try:
    while True:
        if select.select([sys.stdin], [], [], 0)[0]:
            key = sys.stdin.read(1)
            if key == 'q':
                input_pin.irq(handler=None)
                trigger_pin.value(0)
                print("Killed.")
                break
        print(f"Pulse count: {pulse_count} ", end="\r")
        time.sleep_ms(500)

except KeyboardInterrupt:
    input_pin.irq(handler=None)
    trigger_pin.value(0)
    print("Killed.")