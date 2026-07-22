#!/usr/bin/env python3
"""Test the demo player by loading a demo file and checking the console output."""

from playwright.sync_api import sync_playwright
import os

DEMO_PATH = os.path.abspath("demos/territory.ru--vs-Virtus.pro-hltv-0411281802-de_inferno.dem")

console_messages = []

def handle_console(msg):
    # Capture ALL console messages
    text = msg.text
    msg_type = msg.type
    console_messages.append("[" + msg_type + "] " + text)

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()

    # Capture all console output including errors
    page.on("console", handle_console)
    page.on("pageerror", lambda err: console_messages.append("[ERROR] " + str(err)))

    print("Navigating to localhost:5173...")
    page.goto("http://localhost:5173")
    page.wait_for_load_state("networkidle")

    print("Loading demo file...")
    drop_zone = page.locator(".drop-zone")

    with page.expect_file_chooser() as fc_info:
        drop_zone.click()

    file_chooser = fc_info.value
    file_chooser.set_files(DEMO_PATH)

    print("Waiting for demo to load...")
    page.wait_for_timeout(15000)

    page.screenshot(path="/tmp/demo_player_loaded.png", full_page=True)

    print("")
    print("=== ALL Console Messages (" + str(len(console_messages)) + ") ===")
    for i, msg in enumerate(console_messages):
        print(str(i) + ": " + msg[:200])  # Truncate long messages

    browser.close()
