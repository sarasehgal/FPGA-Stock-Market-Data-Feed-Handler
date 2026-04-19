"""Diagnostic: send one frame, sniff ALL traffic on interface for 3 seconds."""
import struct, time, sys
from scapy.all import Ether, Raw, sendp, sniff, conf

IFACE = "Ethernet"
ETHERTYPE_RX = 0x88B5

# Build one simple quote frame: AAPL bid price=123456 qty=100 seq=1
def build():
    sym = b"AAPL"
    payload = struct.pack(">B4sIHHB", 0x01, sym, 123456, 100, 1, 0)
    payload += bytes([sum(payload) & 0xFF])
    return payload

payload = build()
pkt = Ether(dst="ff:ff:ff:ff:ff:ff", src="de:ad:be:ef:ca:fe", type=ETHERTYPE_RX) / Raw(load=payload)

print(f"Sending 1 frame on {IFACE}")
print(f"  Dst: ff:ff:ff:ff:ff:ff  Type: 0x{ETHERTYPE_RX:04X}")
print(f"  Payload ({len(payload)} bytes): {payload.hex()}")
print(f"  Full frame ({len(bytes(pkt))} bytes): {bytes(pkt).hex()}")
print()

sendp(pkt, iface=IFACE, verbose=True)
print("\nFrame sent. Sniffing ALL traffic for 3 seconds...\n")

pkts = sniff(iface=IFACE, timeout=3)
print(f"Captured {len(pkts)} total packets")
for i, p in enumerate(pkts[:20]):
    eth = p[Ether] if p.haslayer(Ether) else None
    if eth:
        raw_bytes = bytes(p[Raw].load) if p.haslayer(Raw) else b""
        print(f"  [{i:2d}] {eth.src} -> {eth.dst}  type=0x{eth.type:04X}  "
              f"len={len(raw_bytes)}  data={raw_bytes[:20].hex()}")
    else:
        print(f"  [{i:2d}] non-Ethernet: {p.summary()}")

# Look specifically for anything from FPGA MAC
fpga_pkts = [p for p in pkts if p.haslayer(Ether) and p[Ether].src.lower() == "00:11:22:33:44:55"]
print(f"\nPackets from FPGA MAC (00:11:22:33:44:55): {len(fpga_pkts)}")
for p in fpga_pkts:
    print(f"  type=0x{p[Ether].type:04X}  data={bytes(p[Raw].load).hex() if p.haslayer(Raw) else 'none'}")
