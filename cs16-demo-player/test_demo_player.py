#!/usr/bin/env python3
"""Test script to verify the CS 1.6 Demo Player is working correctly."""

from playwright.sync_api import sync_playwright
import os
import time

DEMO_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "demos", "territory.ru--vs-Virtus.pro-hltv-0411281802-de_inferno.dem")

def test_demo_player():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        # Capture console logs
        console_logs = []
        def handle_console(msg):
            text = msg.text[:300] if len(msg.text) > 300 else msg.text
            console_logs.append(f"{msg.type}: {text}")
        page.on("console", handle_console)

        print("1. Navigating to demo player...")
        page.goto('http://localhost:5173')
        page.wait_for_load_state('networkidle')
        print("   Page loaded")

        # Click the drop zone to trigger file input creation
        print("\n2. Loading demo file...")
        drop_zone = page.locator('.drop-zone')

        # Use filechooser event to handle the file input that gets created on click
        with page.expect_file_chooser() as fc_info:
            drop_zone.click()
        file_chooser = fc_info.value
        file_chooser.set_files(DEMO_FILE)
        print(f"   Demo file selected: {DEMO_FILE.split('/')[-1]}")

        # Wait for demo to load and parse
        print("   Waiting for demo to parse...")
        time.sleep(8)

        # Take screenshot after demo loads
        page.screenshot(path='/tmp/demo_player_loaded.png', full_page=True)
        print("   Screenshot saved: /tmp/demo_player_loaded.png")

        # Print relevant console logs
        print("\n3. Console output (demo parsing):")
        for log in console_logs:
            if any(x in log.lower() for x in ['playback', 'timeline', 'entries', 'buffer', 'frame', 'netmsg', 'demo loaded', 'player', 'svc', 'entity', 'packet', 'baseline', 'delta', 'raw bytes', 'valid', 'potential', 'scanning', 'found', 'clientdata', 'camera', 'pos=(']):
                print(f"   {log}")

        # Check if Play button is visible and click it
        print("\n4. Starting playback...")
        play_btn = page.locator('#play-btn')
        if play_btn.is_visible():
            play_btn.click()
            print("   Play button clicked")

        # Take screenshots during playback
        print("\n5. Taking screenshots during playback...")
        for i in range(5):
            time.sleep(1.5)
            page.screenshot(path=f'/tmp/demo_player_play_{i+1}.png', full_page=True)
            print(f"   Screenshot {i+1} saved: /tmp/demo_player_play_{i+1}.png")

        # Print position updates from console
        print("\n6. Player position updates:")
        position_logs = [log for log in console_logs if 'raw=' in log.lower() or 'three.js=' in log.lower()]
        for log in position_logs[:10]:
            print(f"   {log}")

        if len(position_logs) > 10:
            print(f"   ... and {len(position_logs) - 10} more position updates")

        # Check for RefParams/spectator camera logs
        print("\n7. Spectator camera info:")
        camera_logs = [log for log in console_logs if 'refparam' in log.lower() or 'spectator' in log.lower() or 'camera' in log.lower()]
        for log in camera_logs[:10]:
            print(f"   {log}")

        browser.close()
        print("\nTest complete!")
        return len(position_logs) > 0

if __name__ == "__main__":
    success = test_demo_player()
    print(f"\nResult: {'PASS - Position updates detected' if success else 'FAIL - No position updates'}")
