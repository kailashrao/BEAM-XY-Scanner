# baud_test.py
# Updated 5/16/2026 by Kailash Rao

# Find the current baud rate of motor controller

import serial, time

PORT = '/dev/tty.usbserial-BG00NHQR'
BAUDS = [9600, 19200, 38400, 57600, 115200]

for baud in BAUDS:
    ser = serial.Serial(PORT, baud, timeout=1)
    ser.write(b'@00ID\r')
    time.sleep(0.5)
    response = ser.read(64)
    print(f'Baud {baud}: {repr(response)}')
    ser.close()
    time.sleep(0.2)