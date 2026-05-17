# motor_control.py
# Updated 5/16/2026 by Kailash Rao

# Meander Scan algorithm for XY scanner 
# Generate measurement triggers to create (STEP_X * NXpixel) * (STEP_Y * NYpixel) array
# Motor stops at each measurement, uses controller reported motor position

import serial
import time

# --- Serial setup ---
PORT = '/dev/tty.usbserial-BG00NHQR'
DEVICE = '00'
BAUD = 57600

ser = serial.Serial(
    port=PORT,
    baudrate=BAUD,
    bytesize=serial.EIGHTBITS,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_ONE,
    timeout=0.2,
    write_timeout=1,
    inter_byte_timeout=0.001 # Micro-delay to ensure RS-485 switch stability
)
def safe_init():
    """Wakes up the controller and clears the line."""
    # 1. Clear macOS system buffers
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    
    # 2. Send two CRs to clear the controller's internal parser
    ser.write(b'\r\r')
    time.sleep(0.1) 
    
    # 3. Clear any junk response from the wake-up
    ser.reset_input_buffer()

def send_command(command):
    full_cmd = f" @{DEVICE}{command}\r"
    ser.write(full_cmd.encode('ascii'))
    response = ser.read_until(b'\r')
    return response.decode('ascii').strip()

def wait_for_x():
    """Wait until X axis is idle."""
    while True:
        status = int(send_command('MSTX'))
        if status == 0 or status == 16 or status == 32:
            break

def wait_for_y():
    """Wait until Y axis is idle."""
    while True:
        status = int(send_command('MSTY'))
        if status == 0 or status == 16 or status == 32:
            break

# --- Conversion factor ---
# 1 mm = 133.333 motor steps
MM_TO_STEPS = 133.333

# --- Object dimension parameters ---
Initial_X = 0   # mm
Initial_Y = 0   # mm
Step_X = 10     # mm
Step_Y = 10     # mm
NXpixel = 5
NYpixel = 5

# --- Calculate motor parameters ---
INIT_X = MM_TO_STEPS * Initial_X
INIT_Y = MM_TO_STEPS * Initial_Y
STP_X  = MM_TO_STEPS * Step_X
STP_Y  = MM_TO_STEPS * Step_Y

# --- Initialize controller ---
safe_init()
send_command('CLR')
send_command('EO=0')
time.sleep(1)
send_command('EO=3')
send_command('HSPD=2000')
send_command('ACC=100')

# --- Go to origin ---
send_command('ABS')
send_command(f'X{int(INIT_X)}')
send_command(f'Y{int(INIT_Y)}')
wait_for_x()
wait_for_y()

# --- Meander scan ---
for i in range(1, NYpixel + 1):
    if i % 2 != 0:  # Odd row — scan left to right
        for j in range(1, NXpixel + 1):
            send_command(f'X{int(j * STP_X)}')
            time.sleep(0.5)
            wait_for_x()
            # TODO: acquire data here
    else:           # Even row — scan right to left
        for j in range(NXpixel, 0, -1):
            send_command(f'X{int(j * STP_X)}')
            time.sleep(0.5)
            wait_for_x()
            # TODO: acquire data here

    send_command(f'Y-{int(i * STP_Y)}')   # +Y direction is downward
    wait_for_y()

    print(f'Row {i} complete')

# --- Return to origin ---
send_command('X0')
send_command('Y0')
wait_for_x()
wait_for_y()
print('Scan complete, returned to origin')

ser.close()