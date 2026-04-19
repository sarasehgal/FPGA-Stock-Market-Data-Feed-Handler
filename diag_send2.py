"""Diagnostic: try all interfaces, send+capture with promiscuous mode."""
import struct, time, sys, threading
from scapy.all import (Ether, Raw, sendp, sniff, conf, get_if_list, IFACES)

ETHERTYPE_RX = 0x88B5

def build_quote():
    payload = struct.pack(">B4sIHHB", 0x01, b"AAPL", 123456, 100, 1, 0)
    return payload + bytes([sum(payload) & 0xFF])

# Find the Realtek Ethernet interface
eth_iface = None
for name, iface in IFACES.items():
    try:
        if "realtek" in (iface.description or "").lower():
            eth_iface = iface
            break
    except:
        pass

if eth_iface is None:
    print("ERROR: Could not find Realtek Ethernet adapter")
    for name, iface in IFACES.items():
        print(f"  {name}: {getattr(iface, 'description', '?')}")
    sys.exit(1)

iface_name = eth_iface.name
print(f"Using interface: {iface_name}")
print(f"  Description: {eth_iface.description}")
print(f"  MAC: {eth_iface.mac}")
print()

# Build packet
payload = build_quote()
pkt = Ether(dst="ff:ff:ff:ff:ff:ff", src=eth_iface.mac, type=ETHERTYPE_RX) / Raw(load=payload)
print(f"Frame: {bytes(pkt).hex()}")
print()

# Try sniffing in background thread
results = []
def sniffer():
    pkts = sniff(iface=iface_name, timeout=5, promisc=True)
    results.extend(pkts)

t = threading.Thread(target=sniffer, daemon=True)
t.start()
time.sleep(0.5)  # let sniffer start

# Send 3 copies
for i in range(3):
    print(f"Sending frame {i+1}/3...")
    sendp(pkt, iface=iface_name, verbose=False)
    time.sleep(0.2)

print("Waiting for sniffer (5 seconds)...")
t.join(timeout=8)

print(f"\nCaptured {len(results)} packets total")
for i, p in enumerate(results[:30]):
    if p.haslayer(Ether):
        eth = p[Ether]
        data = bytes(p[Raw].load).hex()[:40] if p.haslayer(Raw) else "no-payload"
        print(f"  [{i:2d}] {eth.src} -> {eth.dst}  type=0x{eth.type:04X}  {data}")

# Look for FPGA response
fpga = [p for p in results if p.haslayer(Ether)
        and p[Ether].src.lower() == "00:11:22:33:44:55"]
print(f"\nFPGA responses: {len(fpga)}")
# Look for our own frames echoed back
own = [p for p in results if p.haslayer(Ether)
       and p[Ether].type == ETHERTYPE_RX]
print(f"Own frames seen: {len(own)}")
