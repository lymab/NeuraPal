#!/usr/bin/env python3
"""Fix settings screenshots by navigating directly to settings.php"""

import os
import time
from playwright.sync_api import sync_playwright

BASE_URL = "https://sadiky.com"
OUTPUT_DIR = "/Users/lyaz/neurapal-ios/new-screenshots"

DEVICES = {
    "iphone67": {
        "viewport": {"width": 430, "height": 932},
        "device_scale_factor": 3,
        "is_mobile": True,
    },
    "iphone65": {
        "viewport": {"width": 414, "height": 896},
        "device_scale_factor": 3,
        "is_mobile": True,
    },
    "ipad_pro_129": {
        "viewport": {"width": 1024, "height": 1366},
        "device_scale_factor": 2,
        "is_mobile": False,
    },
}


def fix_settings():
    with sync_playwright() as p:
        for device_name, device_config in DEVICES.items():
            device_dir = os.path.join(OUTPUT_DIR, device_name)
            print(f"=== Fixing {device_name} settings ===")

            browser = p.chromium.launch(headless=True)
            ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15" if device_config["is_mobile"] else "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"
            context = browser.new_context(
                viewport=device_config["viewport"],
                device_scale_factor=device_config["device_scale_factor"],
                user_agent=ua,
                is_mobile=device_config["is_mobile"],
            )
            page = context.new_page()

            # Login with demo
            page.goto(f"{BASE_URL}/login.php", wait_until="networkidle", timeout=30000)
            time.sleep(2)
            demo_btn = page.query_selector('a:has-text("Try a Demo"), button:has-text("Try a Demo"), a:has-text("Try Demo"), button:has-text("Try Demo")')
            if demo_btn:
                demo_btn.click()
                time.sleep(5)
                print(f"  Logged in: {page.url}")

                # Navigate directly to settings
                page.goto(f"{BASE_URL}/settings.php", wait_until="networkidle", timeout=30000)
                time.sleep(3)
                page.screenshot(path=os.path.join(device_dir, "settings.png"))
                print(f"  settings ✓")

                # Also check if page.url is still settings
                print(f"  Final URL: {page.url}")

            browser.close()


if __name__ == "__main__":
    fix_settings()
