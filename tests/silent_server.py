import socket, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 5678)); s.listen(64)
print("silent listener on 127.0.0.1:5678", flush=True)
conns = []
t0 = time.time()
while time.time() - t0 < 1800:          # long enough for a full test run
    s.settimeout(1.0)
    try:
        c, _ = s.accept(); conns.append(c)   # accept, then stay silent forever
    except socket.timeout:
        pass
