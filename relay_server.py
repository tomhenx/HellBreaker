"""
HellBreaker WebSocket Relay Server
===================================
Deploy free to: Render.com, Fly.io, Railway.app

Install:  pip install websockets
Run:      python relay_server.py          (local, port 8765)
          PORT=8765 python relay_server.py

Packet protocol (binary):
  System packets  (5 bytes):  [0xFF][type:1][peer_id:4 LE]
    type 0 = peer added, 1 = peer removed, 2 = your ID assigned
  Data packets    (8+ bytes): [target:4 LE][source:4 LE][payload...]
    target 0 = broadcast to all except sender
    relay strips target/source from what it delivers, re-adds source
"""

import asyncio
import json
import os
import random
import string
import struct
import websockets

# ── State ─────────────────────────────────────────────────────────────────────

rooms: dict[str, dict] = {}
# rooms[code] = { "host": ws, "peers": {peer_id: ws}, "next_id": 3 }

# ── Helpers ───────────────────────────────────────────────────────────────────

def _gen_code() -> str:
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))

def _sys(type_byte: int, peer_id: int) -> bytes:
    return struct.pack("<BBi", 0xFF, type_byte, peer_id)

async def _send(ws, data):
    try:
        await ws.send(data)
    except Exception:
        pass

async def _send_json(ws, obj: dict):
    await _send(ws, json.dumps(obj))

async def _broadcast(room: dict, data: bytes, exclude_ws=None):
    for ws in list(room["peers"].values()):
        if ws is not exclude_ws:
            await _send(ws, data)
    if room["host"] and room["host"] is not exclude_ws:
        await _send(room["host"], data)

# ── Connection handler ────────────────────────────────────────────────────────

async def handler(ws):
    code = None
    peer_id = None
    is_host = False
    room = None

    try:
        # First message must be JSON control message
        raw = await asyncio.wait_for(ws.recv(), timeout=10)
        msg = json.loads(raw)
        role = msg.get("role", "")

        if role == "list":
            public_rooms = []
            for rcode, rdata in list(rooms.items()):
                if rdata.get("public", True):
                    public_rooms.append({
                        "code":    rcode,
                        "host":    rdata.get("host_name", "Unknown"),
                        "players": len(rdata["peers"]) + 1,
                        "max":     4,
                    })
            await _send_json(ws, {"type": "rooms", "rooms": public_rooms})
            return

        elif role == "host":
            # Generate unique room code
            code = _gen_code()
            while code in rooms:
                code = _gen_code()
            host_name = msg.get("name", "Unknown")
            is_public  = bool(msg.get("public", True))
            room = {"host": ws, "peers": {}, "next_id": 2,
                    "host_name": host_name, "public": is_public}
            rooms[code] = room
            is_host = True
            peer_id = 1

            # Tell host its ID and its room code
            await _send(ws, _sys(2, 1))
            await _send_json(ws, {"type": "room_code", "code": code})
            print(f"[+] Host created room {code} (public={is_public})")

        elif role == "client":
            code = msg.get("code", "").upper().strip()
            if code not in rooms:
                await _send_json(ws, {"type": "error", "msg": "Room not found"})
                return
            room = rooms[code]
            peer_id = room["next_id"]
            room["next_id"] += 1
            room["peers"][peer_id] = ws
            is_host = False

            # Tell new client its ID
            await _send(ws, _sys(2, peer_id))
            # Tell new client about existing peers
            await _send(ws, _sys(0, 1))  # host always exists
            for pid in room["peers"]:
                if pid != peer_id:
                    await _send(ws, _sys(0, pid))
            # Tell all existing peers about the new client
            await _broadcast(room, _sys(0, peer_id), exclude_ws=ws)
            print(f"[+] Client {peer_id} joined room {code}")

        else:
            return

        # ── Relay loop ──────────────────────────────────────────────────────
        async for data in ws:
            if not isinstance(data, bytes) or len(data) < 4:
                continue

            target = struct.unpack_from("<I", data, 0)[0]
            payload = data[4:]  # everything after the 4-byte target
            source_bytes = struct.pack("<I", peer_id)
            out = source_bytes + payload  # relay prepends source_id

            if target == 0:
                # Broadcast
                await _broadcast(room, out, exclude_ws=ws)
            elif target == 1:
                # To host
                if room["host"]:
                    await _send(room["host"], out)
            else:
                # To specific client
                dest = room["peers"].get(target)
                if dest:
                    await _send(dest, out)

    except (websockets.exceptions.ConnectionClosed, asyncio.TimeoutError):
        pass
    except Exception as e:
        print(f"[!] Error: {e}")
    finally:
        # Clean up
        if room is None:
            return
        if is_host:
            # Notify all clients server is gone
            await _broadcast(room, _sys(1, 1))
            del rooms[code]
            print(f"[-] Host closed room {code}")
        elif peer_id and peer_id in room.get("peers", {}):
            del room["peers"][peer_id]
            await _broadcast(room, _sys(1, peer_id))
            print(f"[-] Client {peer_id} left room {code}")


# ── Main ──────────────────────────────────────────────────────────────────────

async def main():
    import ssl as _ssl
    port     = int(os.environ.get("PORT", 8765))
    tls_cert = os.environ.get("TLS_CERT", "")
    tls_key  = os.environ.get("TLS_KEY",  "")

    ssl_ctx = None
    if tls_cert and tls_key:
        ssl_ctx = _ssl.SSLContext(_ssl.PROTOCOL_TLS_SERVER)
        ssl_ctx.load_cert_chain(tls_cert, tls_key)
        print(f"TLS enabled ({tls_cert})")

    print(f"HellBreaker relay listening on 0.0.0.0:{port}")
    async with websockets.serve(handler, "0.0.0.0", port, ssl=ssl_ctx):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
