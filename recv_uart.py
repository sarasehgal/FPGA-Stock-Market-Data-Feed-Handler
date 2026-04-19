"""recv_uart.py - listen on the FPGA's USB-UART for trigger messages.

Auto-detects the COM port (looks for FTDI / USB Serial Device).
Override with --port COMx if needed.
"""
import sys, time, argparse
import serial
from serial.tools import list_ports

def find_port():
    ports = list(list_ports.comports())
    print("Available COM ports:")
    for p in ports:
        print(f"  {p.device}  {p.description}  {p.hwid}")
    # Prefer FTDI / Xilinx / Digilent
    for p in ports:
        d = (p.description + p.hwid).lower()
        if any(k in d for k in ['ftdi', 'xilinx', 'digilent', 'usb serial', 'urbana']):
            print(f"-> Auto-selected {p.device}")
            return p.device
    if ports:
        print(f"-> Defaulting to first port {ports[0].device}")
        return ports[0].device
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', default=None)
    ap.add_argument('--baud', type=int, default=115200)
    args = ap.parse_args()

    port = args.port or find_port()
    if not port:
        print("ERROR: no serial port found")
        sys.exit(1)

    print(f"Opening {port} at {args.baud} 8N1...")
    ser = serial.Serial(port, args.baud, bytesize=8, parity='N', stopbits=1, timeout=1)
    print("Listening (Ctrl+C to stop):")
    buf = b''
    try:
        while True:
            chunk = ser.read(256)
            if chunk:
                buf += chunk
                while b'\n' in buf:
                    line, buf = buf.split(b'\n', 1)
                    line = line.rstrip(b'\r')
                    try:
                        s = line.decode('ascii', errors='replace')
                    except Exception:
                        s = repr(line)
                    print(f"[{time.strftime('%H:%M:%S')}] {s}")
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()

if __name__ == '__main__':
    main()
