# change_baud.py
# Updated 5/16/2026 by Kailash Rao

# Change baud rate from current to target

import serial
import time

# --- Configuration ---
PORT = '/dev/tty.usbserial-BG00NHQR'
DEVICE = '00'
CURRENT_BAUD = 38400  # Change this to match your current setting

BAUD_MAP = {
    "9600": 1,
    "19200": 2,
    "38400": 3,
    "57600": 4,
    "115200": 5
}

def send_command(ser, command):
    full_cmd = f"@{DEVICE}{command}\r"
    ser.write(full_cmd.encode('ascii'))
    time.sleep(0.2)
    response = ser.read_until(b'\r')
    return response.decode('ascii').strip()

def main():
    print(f"Connecting to {PORT} at {CURRENT_BAUD} baud...")
    try:
        ser = serial.Serial(PORT, CURRENT_BAUD, timeout=1)
    except Exception as e:
        print(f"Error opening port: {e}")
        return

    print("\nAvailable Baud Rates:")
    for b in BAUD_MAP.keys():
        print(f"- {b}")
    
    target = input("\nEnter target baud rate: ").strip()
    
    if target not in BAUD_MAP:
        print("Invalid choice. Please choose from the list above.")
        ser.close()
        return

    baud_code = BAUD_MAP[target]
    
    print(f"Changing baud rate to {target} (Code {baud_code})...")
    
    # Send DB command to set baud rate
    resp1 = send_command(ser, f"DB={baud_code}")
    print(f"Controller: {resp1}")
    
    # Send STORE command to save to flash
    resp2 = send_command(ser, "STORE")
    print(f"Controller (Flash Store): {resp2}")
    
    print("\n" + "="*40)
    print("SUCCESS: Settings updated.")
    print("IMPORTANT: You must POWER CYCLE the controller now.")
    print(f"After restarting, update your scripts to use {target} baud.")
    print("="*40)

    ser.close()

if __name__ == "__main__":
    main()