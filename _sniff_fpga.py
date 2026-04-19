"""Sniff incoming traffic on Realtek NIC, look for FPGA frames."""
from scapy.all import sniff, Ether, Raw

IFACE = r'\Device\NPF_{696EC36D-E991-4A75-8002-E3C10A7430A6}'

print('Listening 30s on Realtek for any inbound frames...')
pkts = sniff(iface=IFACE, timeout=30, promisc=True)
print(f'Total: {len(pkts)}')

# All ethertype distribution
from collections import Counter
etcnt = Counter()
for p in pkts:
    if p.haslayer(Ether):
        etcnt[(p[Ether].src, hex(p[Ether].type))] += 1
print('\\n(src_mac, ethertype) counts:')
for (s, t), c in etcnt.most_common(20):
    print(f'  {s} type={t}: {c}')

# Specifically look for FPGA MAC
fpga_macs = ['00:11:22:33:44:55', '01:80:c2:fe:dc:ba']
for p in pkts:
    if p.haslayer(Ether) and p[Ether].src.lower() in [m.lower() for m in fpga_macs]:
        raw = bytes(p[Raw].load) if p.haslayer(Raw) else b''
        print(f'  FPGA: src={p[Ether].src} dst={p[Ether].dst} type=0x{p[Ether].type:04X} payload={raw.hex()}')

# Also look for any ethertype 0x88B5 (the response type if FPGA echoes our type) or 0x0800
for p in pkts:
    if p.haslayer(Ether) and p[Ether].type in (0x88B5, 0x0800, 0xABCD):
        raw = bytes(p[Raw].load) if p.haslayer(Raw) else b''
        print(f'  Etype: src={p[Ether].src} dst={p[Ether].dst} type=0x{p[Ether].type:04X} payload={raw.hex()[:40]}')
