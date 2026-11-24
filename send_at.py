import sys
import time
import re
import socket

def run_at_commands(cmds, host='192.168.0.1', wait_time=0.8):
    results = {}
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5.0)
        s.connect((host, 23)) # Telnet port 23 is instant and unauthenticated root shell
        time.sleep(0.3)
        s.recv(4096)
        
        s.sendall(b"exec 3<>/dev/smd11\n")
        time.sleep(0.2)
        s.recv(4096)
        
        for cmd in cmds:
            payload = f'echo -e "{cmd}\\r" >&3; cat <&3 &\nPID=$!\nsleep {wait_time}\nkill -9 $PID 2>/dev/null\n'
            s.sendall(payload.encode('utf-8'))
            time.sleep(wait_time + 0.3)
            raw = s.recv(8192).decode('utf-8', errors='ignore')
            
            lines = [l.strip('\r') for l in raw.split('\n')]
            cleaned = []
            capture = False
            for line in lines:
                if cmd in line and not capture:
                    capture = True
                    continue
                if "kill -9" in line:
                    break
                if capture and not line.startswith("root@sdxlemur") and not line.startswith("[1]"):
                    cleaned.append(line)
            res = "\n".join(cleaned).strip()
            results[cmd] = res if res else raw
            
        s.sendall(b"exec 3>&-\nexit\n")
        s.close()
    except Exception as e:
        results["error"] = str(e)
    return results

if __name__ == '__main__':
    commands = sys.argv[1:] if len(sys.argv) > 1 else ['ATI']
    res = run_at_commands(commands)
    for c in commands:
        print(f"=== {c} ===")
        print(res.get(c, ''))

