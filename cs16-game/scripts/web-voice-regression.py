"""Browser voice end to end: a local dedicated server, the web export served
over HTTP, and three Chrome players. A and B join T, C joins CT; A holds
push-to-talk with a generated tone as its microphone. B must decode A's audio
at full level and list A as talking; C (other team) must receive nothing.

Requires the web export (npm run game:build:web) and Google Chrome."""
import json, math, os, socket, struct, subprocess, sys, tempfile, time, wave
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "game" / "builds" / "web"


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def write_tone(path: Path) -> None:
    # 125 ms bursts of a warbling tone: speech-like enough for the browser's
    # noise suppression to pass it.
    rate = 48000
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1); out.setsampwidth(2); out.setframerate(rate)
        frames = bytearray()
        for i in range(rate * 6):
            t = i / rate
            on = 1.0 if int(t * 4) % 2 == 0 else 0.0
            value = 0.5 * on * math.sin(2 * math.pi * (300 + 200 * math.sin(2 * math.pi * 3 * t)) * t)
            frames += struct.pack("<h", int(value * 32767))
        out.writeframes(bytes(frames))


def main() -> int:
    if not (WEB / "voice.js").is_file() or not (WEB / "index.pck").is_file():
        print("web export missing: run npm run game:build:web", file=sys.stderr)
        return 1
    work = Path(tempfile.mkdtemp(prefix="protocol47-web-voice-"))
    tone = work / "tone.wav"
    write_tone(tone)
    port = free_port()
    server = subprocess.Popen(
        ["godot", "--headless", "--audio-driver", "Dummy", "--log-file", str(work / "server.log"),
         "--path", str(ROOT / "game"), "--", "--dedicated", f"--port={port}"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        env={**os.environ, "PROTOCOL47_SETTINGS_PATH": str(work / "server.cfg")})
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), partial(SimpleHTTPRequestHandler, directory=str(WEB)))
    Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        deadline = time.time() + 60
        while time.time() < deadline:
            line = server.stdout.readline()
            if f"WebSocket {port + 1}" in line:
                break
        else:
            print("server did not start", file=sys.stderr)
            return 1
        url = f"http://127.0.0.1:{httpd.server_address[1]}/index.html?server=ws://127.0.0.1:{port + 1}"
        with sync_playwright() as p:
            browser = p.chromium.launch(channel="chrome", headless=True, args=[
                "--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream",
                f"--use-file-for-fake-audio-capture={tone}", "--autoplay-policy=no-user-gesture-required"])
            pages = {}
            for name in ("A", "B", "C"):
                page = browser.new_context(viewport={"width": 1280, "height": 720}, permissions=["microphone"]).new_page()
                page.logs = []
                page.on("console", lambda message, pg=page: pg.logs.append(message.text))
                page.goto(url)
                pages[name] = page
            for page in pages.values():
                start = time.time()
                while time.time() - start < 60 and not any("CONNECTED" in line for line in page.logs):
                    page.wait_for_timeout(250)
            for name, page in pages.items():
                page.wait_for_timeout(2000)
                page.mouse.click(640, 360)
                page.keyboard.press("2" if name == "C" else "1"); page.wait_for_timeout(800)
                page.keyboard.press("1"); page.wait_for_timeout(2000)
            a, b, c = pages["A"], pages["B"], pages["C"]
            a.keyboard.down("k"); a.wait_for_timeout(2500)
            talking = b.evaluate("P47Voice.talking()")
            a.wait_for_timeout(500); a.keyboard.up("k"); b.wait_for_timeout(1200)
            sa, sb, sc = (json.loads(page.evaluate("P47Voice.stats()")) for page in (a, b, c))
            browser.close()
        print(f"A sent {sa['framesSent']}; B decoded {sb['framesDecoded']} (peak {sb['maxDecodedPeak']:.2f}, talking {talking!r}); C received {sc['framesReceived']}")
        ok = (sa["framesSent"] > 100 and sb["framesDecoded"] >= sa["framesSent"] * 0.95
              and sb["maxDecodedPeak"] > 0.3 and sc["framesReceived"] == 0 and bool(talking))
        print("GAME_WEB_VOICE_PASS" if ok else "GAME_WEB_VOICE_FAIL")
        return 0 if ok else 1
    finally:
        httpd.shutdown()
        server.terminate()
        server.wait(timeout=20)


if __name__ == "__main__":
    sys.exit(main())
