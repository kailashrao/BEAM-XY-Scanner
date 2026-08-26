# home.py
# Updated 7/6/2026 by Kailash Rao

# Homing script for the NSC-A2L XY scanner that sets the origin at the bottom-left

import serial
import time

# --- Serial setup ---
PORT = 'COM4'  # Windows
DEVICE = '00'
BAUD = 57600
TIMEOUT = 0.2

ser = serial.Serial(
    port=PORT,
    baudrate=BAUD,
    bytesize=serial.EIGHTBITS,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_ONE,
    timeout=TIMEOUT,
    write_timeout=1,
    inter_byte_timeout=0.001,
)

# Homing speeds and acceleration
HSPD = 10000
LSPD = 1000
ACC = 300


def send_command(command: str) -> str:
    full = f" @{DEVICE}{command}\r"
    ser.write(full.encode('ascii'))
    response = ser.read_until(b'\r')
    return response.decode('ascii').strip()


def safe_init() -> None:
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    ser.write(b'\r\r')
    time.sleep(0.1)
    ser.reset_input_buffer()


def wait_for_x() -> None:
    while True:
        status = int(send_command('MSTX') or 0)
        # Bits 0, 1, 2 represent Accel, Decel, and Constant Speed. 
        if (status & 7) == 0:
            break


def wait_for_y() -> None:
    while True:
        status = int(send_command('MSTY') or 0)
        if (status & 7) == 0:
            break


def home_x() -> None:
    print("Homing X axis to the negative limit switch (left)...")
    send_command('LX-') 
    wait_for_x()
    
    print("  Setting X origin (0)...")
    send_command('ABS')
    send_command('X0')
    wait_for_x()
    print("  X axis homing complete.")


def home_y() -> None:
    print("Homing Y axis to the negative limit switch (bottom)...")
    send_command('LY+')
    wait_for_y()
    
    print("  Setting Y origin (0)...")
    send_command('ABS')
    send_command('Y0')
    wait_for_y()
    print("  Y axis homing complete.")


def initialize_controller() -> None:
    safe_init()
    send_command('CLR')
    send_command(f'HSPD={HSPD}')
    send_command(f'LSPD={LSPD}')
    send_command(f'ACC={ACC}')


if __name__ == '__main__':
    try:
        initialize_controller()
        # Home to the negative limits to establish bottom-left as 0,0
        home_x()
        home_y()
        print("All axes successfully homed to the bottom-left origin.")
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        ser.close()