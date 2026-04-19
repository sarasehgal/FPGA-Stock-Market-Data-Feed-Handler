"""Full test: send 8 frames, capture ALL traffic, look for any non-self packets."""
import struct, time, threading
from scapy.all import Ether, Raw, sendp, sniff

IFACE = "Ethernet"
SRC = "d4:a2:cd:1c:a9:0b"

def build(mt, sym, price, qty, seq, side):
    payload = struct.pack(">B4sIHHB", mt, sym, price, qty, seq, side)
    return payload + bytes([sum(payload) & 0xFF])

results = []
def rx():
    pkts = sniff(iface=IFACE, timeout=20, promisc=True)
    results.extend(pkts)

t = threading.Thread(target=rx, daemon=True)
t.start()
time.sleep(1)

frames = [
    (0x01, b"AAPL", 123456, 100, 42, 0, "Quote AAPL bid - TRIGGER"),
    (0x02, b"MSFT", 223344, 250, 43, 1, "Trade MSFT ask - TRIGGER"),
    (0x03, b"AAPL", 0,      0,   44, 0, "Cancel AAPL"),
    (0x04, b"NVDA", 0,      0,   45, 0, "Halt NVDA"),
    (0x01, b"NVDA", 998877, 75,  46, 0, "Quote NVDA halted"),
    (0x05, b"AAPL", 0,      0,   47, 0, "Heartbeat"),
    (0xAB, b"AAPL", 999999, 1,   48, 0, "Unknown"),
    (0x01, b"TSLA", 555555, 10,  49, 0, "Quote TSLA bid - TRIGGER"),
]

print("=== SENDING 8 TEST FRAMES (watch LEDs) ===\n")
for mt, sym, price, qty, seq, side, desc in frames:
    payload = build(mt, sym, price, qty, seq, side)
    pkt = Ether(dst="ff:ff:ff:ff:ff:ff", src=SRC, type=0x88B5) / Raw(load=payload)
    sendp(pkt, iface=IFACE, verbose=False)
    print(f"  [{seq:2d}] {desc}")
    time.sleep(0.3)

print("\nWaiting 8 seconds for responses...\n")
t.join(timeout=12)

# Separate our frames from everything else
our_pkts = []
other_pkts = []
for p in results:
    if p.haslayer(Ether):
        if p[Ether].src.lower() == SRC.lower():
            our_pkts.append(p)
        else:
            other_pkts.append(p)

print(f"Total captured: {len(results)}")
print(f"  From us (src={SRC}): {len(our_pkts)}")
print(f"  From others: {len(other_pkts)}")

if other_pkts:
    print("\n=== NON-SELF PACKETS (possible FPGA responses) ===")
    for i, p in enumerate(other_pkts[:20]):
        eth = p[Ether]
        raw = bytes(p[Raw].load) if p.haslayer(Raw) else b""
        print(f"  [{i}] src={eth.src} dst={eth.dst} type=0x{eth.type:04X} "
              f"len={len(raw)} data={raw[:20].hex()}")

# Also check for type 0x0800 in ALL packets (FPGA uses this ethertype)
resp_0800 = [p for p in results if p.haslayer(Ether) and p[Ether].type == 0x0800]
print(f"\nAll type=0x0800 packets: {len(resp_0800)}")
for i, p in enumerate(resp_0800[:10]):
    eth = p[Ether]
    raw = bytes(p[Raw].load) if p.haslayer(Raw) else b""
    print(f"  [{i}] src={eth.src} dst={eth.dst} len={len(raw)} data={raw[:20].hex()}")

print("\nWhich LEDs flashed? (2=RX, 3=msg parsed, 4=TX, 5=trigger, 8-15=chase)")
