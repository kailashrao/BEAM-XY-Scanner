# trigger.py
# Updated 5/16/2026 by Kailash Rao

# Generate trigger after TRIGGER_EVERY rising edges from encoder

from machine import Pin
import time
import sys
import select

# Input signal on GP15, output trigger on GP14
input_pin = Pin(21, Pin.IN, Pin.PULL_DOWN)
trigger_pin = Pin(20, Pin.OUT)

trigger_pin.value(0)

TRIGGER_EVERY = 5
pulse_count = 0
firing = False

def pulse_handler(pin):
    global pulse_count, firing
    
    if pin.value() == 1:  # Rising edge
        pulse_count += 1
        if pulse_count % TRIGGER_EVERY == 0:
            trigger_pin.value(1)
            firing = True
    else:                 # Falling edge
        if firing:
            trigger_pin.value(0)
            firing = False

# Trigger on BOTH rising and falling edges
input_pin.irq(trigger=Pin.IRQ_RISING | Pin.IRQ_FALLING, handler=pulse_handler)

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
        print(f"Pulse count: {pulse_count}", end="\r")
        time.sleep_ms(500)

except KeyboardInterrupt:
    input_pin.irq(handler=None)
    trigger_pin.value(0)
    print("Killed.")