# test.py
# Updated 5/16/2026 by Kailash Rao

# Test Pico connection by setting GP20 high for 10 seconds

from machine import Pin
import time
p = Pin(20, Pin.OUT)
print("Pulling GP20 High...")
p.value(1)
time.sleep(5)  # holds low for 5 seconds then exits cleanly
p.value(0)