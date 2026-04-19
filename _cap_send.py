import struct, time
from scapy.all import Ether, Raw, sendp
for i in range(400):
    payload = struct.pack('>B4sIHHB', 1, b'AAPL', 123456, 100, i+1, 0)
    payload += bytes([sum(payload) % 256])
    pkt = Ether(dst='ff:ff:ff:ff:ff:ff', src='d4:a2:cd:1c:a9:0b', type=0x88B5) / Raw(load=payload)
    sendp(pkt, iface='Ethernet', verbose=False)
    time.sleep(0.02)
