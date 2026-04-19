"""Send 10 frames to FPGA, capture responses. Watch LEDs."""
import struct, time, threading
from scapy.all import Ether, Raw, sendp, sniff

IFACE = r'\Device\NPF_{696EC36D-E991-4A75-8002-E3C10A7430A6}'  # Realtek PCIe GbE → FPGA PHY
SRC = "d4:a2:cd:1c:a9:0b"

def build(mt, sym, price, qty, seq, side):
    payload = struct.pack(">B4sIHHB", mt, sym, price, qty, seq, side)
    return payload + bytes([sum(payload) & 0xFF])

# Sniffer in background
results = []
def rx():
    pkts = sniff(iface=IFACE, timeout=18, promisc=True)
    results.extend(pkts)

t = threading.Thread(target=rx, daemon=True)
t.start()
time.sleep(0.5)

print("=== WATCH LEDs NOW ===")
print("Sending 10 frames, 1 per second...")
print()
time.sleep(2)

for i in range(10):
    payload = build(0x01, b"AAPL", 123456, 100, i+1, 0)
    pkt = Ether(dst="ff:ff:ff:ff:ff:ff", src=SRC, type=0x88B5) / Raw(load=payload)
    sendp(pkt, iface=IFACE, verbose=False)
    print(f"  Frame {i+1}/10 sent")
    time.sleep(1)

print()
print("Waiting for responses...")
t.join(timeout=8)

# Check all captured traffic
print(f"\nTotal packets captured: {len(results)}")
for i, p in enumerate(results[:30]):
    if p.haslayer(Ether):
        eth = p[Ether]
        raw = bytes(p[Raw].load) if p.haslayer(Raw) else b""
        print(f"  [{i:2d}] {eth.src} -> {eth.dst}  "
              f"type=0x{eth.type:04X}  len={len(raw)}  "
              f"data={raw[:16].hex()}")

# FPGA responses
fpga = [p for p in results
        if p.haslayer(Ether) and p[Ether].src.lower() == "00:11:22:33:44:55"]
print(f"\nFPGA responses (src=00:11:22:33:44:55): {len(fpga)}")
for p in fpga:
    raw = bytes(p[Raw].load) if p.haslayer(Raw) else b""
    if len(raw) >= 15:
        sym = raw[1:5].decode("ascii", errors="replace")
        price = struct.unpack(">I", raw[5:9])[0]
        reason = raw[13]
        print(f"  type=0x{raw[0]:02X} sym={sym} price={price} reason={reason}")
