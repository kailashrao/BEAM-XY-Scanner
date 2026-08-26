# otf_physical_trigger.py
# Updated 06/26/2026 by Kailash Rao

# On-The-Fly Meander Scan algorithm for the XY scanner.
# This script moves the motor in a stop-and-scan meander pattern.
# Measurement triggering or data acquisition should be handled separately 
# (i.e physical trigger from trigger board)

import serial
import time

# --- Serial setup ---
# PORT = '/dev/tty.usbserial-BG00NHQR'  # macOS
PORT = 'COM4'  # Windows
DEVICE = '00'
BAUD = 57600
TIMEOUT = 0.2

MM_TO_STEPS = 133.333

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

NXPIXEL = 50
NYPIXEL = 5
STEP_X_MM = 10
STEP_Y_MM = 10
START_X_MM = 0
START_Y_MM = 0
HSPD = 10000
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
        if status in (0, 16, 32):
            break


def wait_for_y() -> None:
    while True:
        status = int(send_command('MSTY') or 0)
        if status in (0, 16, 32):
            break


def mm_to_steps(value_mm: float) -> int:
    return int(round(value_mm * MM_TO_STEPS))


def move_x(position_mm: float) -> None:
    steps = mm_to_steps(position_mm)
    send_command(f'X{steps}')
    wait_for_x()


def move_y(position_mm: float) -> None:
    steps = mm_to_steps(position_mm)
    send_command(f'Y{steps}')
    wait_for_y()


def meander_scan(nx: int, ny: int, step_x: float, step_y: float, start_x: float = 0.0, start_y: float = 0.0) -> None:
    origin_x = start_x
    origin_y = start_y
    row_length_mm = (nx - 1) * step_x

    for row in range(ny):
        y_target = origin_y - row * step_y
        if row > 0:
            move_y(y_target)

        if row % 2 == 0:
            x_end = origin_x + row_length_mm
            direction = 'left-to-right'
        else:
            x_end = origin_x
            direction = 'right-to-left'

        print(f"Starting row {row+1}/{ny}: Y={y_target:.3f} mm, scanning {direction}")
        move_x(x_end)
        print(f"  Completed row {row+1}/{ny}: X={x_end:.3f} mm")
        # External trigger / measurement capture should occur while X is continuously moving.

    print('Meander scan complete.')


def initialize_controller() -> None:
    safe_init()
    send_command('CLR')
    send_command('ABS')
    send_command(f'HSPD={HSPD}')
    send_command(f'ACC={ACC}')
    send_command(f'X{mm_to_steps(START_X_MM)}')
    send_command(f'Y{mm_to_steps(START_Y_MM)}')


if __name__ == '__main__':
    try:
        initialize_controller()
        meander_scan(NXPIXEL, NYPIXEL, STEP_X_MM, STEP_Y_MM, START_X_MM, START_Y_MM)
        send_command(f'X{mm_to_steps(START_X_MM)}')
        send_command(f'Y{mm_to_steps(START_Y_MM)}')
    finally:
        ser.close()
