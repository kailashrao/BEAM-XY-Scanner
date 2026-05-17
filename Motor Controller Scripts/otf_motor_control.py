# otf_motor_control.py
# Updated 5/16/2026 by Kailash Rao

# On-The-Fly Meander Scan algorithm for XY scanner 
# Generate measurement triggers to create (STEP_X * NXpixel) * (STEP_Y * NYpixel) array
# Motor continues moving through each measurement, uses controller reported motor position

import serial
import time

# --- Setup ---
ser = serial.Serial('/dev/tty.usbserial-BG00NHQR', 57600, timeout=0.1)
DEVICE = '00'
HSPD = 5000  
MM_TO_STEPS = 133.333
BUFFER = int(5 * MM_TO_STEPS)

NXpixel, NYpixel = 5, 5
Step_X, Step_Y = 10, 10

def cmd(c):
    ser.write(f"@{DEVICE}{c}\r".encode())
    return ser.read_until(b'\r').decode().strip()

def wait():
    while int(cmd('MSTX') or 1) != 0: pass

def otf_scan(targets, direction, end_pt):
    cmd(f'X{end_pt}') 
    
    # 1. Wait for Constant Velocity
    while not (int(cmd('MSTX') or 0) & 4): pass
    
    # 2. TUNING: Wait specifically for the motor to cross the 0 / Start point
    # to sync our clock perfectly for PX1
    start_trigger = targets[0]
    while True:
        pos = int(cmd('PX') or 0)
        if (direction == "R" and pos >= start_trigger) or (direction == "L" and pos <= start_trigger):
            t0 = time.perf_counter()
            x0 = pos
            break

    print(f"{'Trig':<5} | {'Actual(st)':<10} | {'Exp(st)':<10} | {'Diff':<8} | {'Act(mm)':<8} | {'Exp(mm)':<8}")
    print("-" * 75)
    
    count = 0
    while count < len(targets):
        actual_x = int(cmd('PX') or 0)
        dt = time.perf_counter() - t0
        expected_x = x0 + ((1 if direction == "R" else -1) * HSPD * dt)
        
        if (direction == "R" and actual_x >= targets[count]) or \
           (direction == "L" and actual_x <= targets[count]):
            diff = actual_x - expected_x
            act_mm = actual_x / MM_TO_STEPS
            exp_mm = expected_x / MM_TO_STEPS
            
            print(f"{count+1:<5} | {actual_x:<10} | {expected_x:<10.1f} | {diff:<8.1f} | {act_mm:<8.2f} | {exp_mm:<8.2f}")
            count += 1
    wait()

# --- Execution ---
cmd('ABS'); cmd(f'HSPD={HSPD}'); cmd('ACC=100')
pixel_coords = [j * Step_X * MM_TO_STEPS for j in range(NXpixel)]

for i in range(NYpixel):
    y_pos = int(i * Step_Y * MM_TO_STEPS)
    cmd(f'Y{y_pos}'); wait()
    print(f"\n[ROW {i+1}] Y: {y_pos} steps ({y_pos/MM_TO_STEPS:.1f} mm)")
    
    if i % 2 == 0:
        cmd(f'X{-BUFFER}'); wait()
        otf_scan(pixel_coords, "R", pixel_coords[-1] + BUFFER)
    else:
        cmd(f'X{pixel_coords[-1] + BUFFER}'); wait()
        otf_scan(pixel_coords[::-1], "L", -BUFFER)

cmd('X0'); cmd('Y0'); wait(); ser.close()