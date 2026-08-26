# motor_test.py
# Updated 5/16/2026 by Kailash Rao

# Move scanner to (X,Y) position

import serial
import time

# PORT = '/dev/tty.usbserial-BG00NHQR' # macOS
PORT = 'COM4'  # Windows
DEVICE = '00'

XPOS = 10000  # Target X position in steps
YPOS = 10000      # Target Y position in steps

ser = serial.Serial(
    port=PORT,
    baudrate=57600,
    bytesize=serial.EIGHTBITS,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_ONE,
    timeout=1
)

def send_command(command):
    full_cmd = f"@{DEVICE}{command}\r"
    ser.write(full_cmd.encode('ascii'))
    time.sleep(0.1)
    response = ser.read_until(b'\r')
    return response.decode('ascii').strip()

# Test
print("ID:", send_command('ID'))       # Performax-2ED-SA
print("VER:", send_command('VER'))      # Firmware version
print("X POS:", send_command('PX'))       # Current X position
print("Y POS:", send_command('PY'))       # Current Y position
print("X STATUS:", send_command('MSTX'))     # X motor status
print("Y STATUS:", send_command('MSTY'))     # Y motor status
print("ENABLE OUTPUT:", send_command('EO'))       # Enable output status

# Set speeds and acceleration
print(send_command('HSPD=5000'))   # Low high-speed (1000 pulses/sec)
print(send_command('LSPD=100'))    # Low start speed
print(send_command('ACC=300'))     # Gentle acceleration

# Enable motor
print(send_command('EO=3'))

# Move X to position 1000 (small move)
print(send_command(f'X{XPOS}'))
print(send_command(f'Y{YPOS}'))

# Poll until idle
while True:
    x_status = send_command('MSTX')
    y_status = send_command('MSTY')
    x_pos = send_command('PX')
    y_pos = send_command('PY')
    print(f'X Status: {x_status}, Position: {x_pos}')
    print(f'Y Status: {y_status}, Position: {y_pos}')
    if int(x_status) & 0b111 == 0 and int(y_status) & 0b111 == 0:
        print('Move complete')
        break
    time.sleep(0.1)