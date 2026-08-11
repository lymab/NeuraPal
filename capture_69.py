#!/usr/bin/env python3
"""Capture 6.9" iPhone screenshots (1320x2868 for iPhone 16 Pro Max)."""

import os
import time
from playwright.sync_api import sync_playwright

BASE_URL = "https://sadiky.com"
OUTPUT_DIR = "/Users/lyaz/neurapal-ios/new-screenshots/iphone69"

HIDE_CONTROLS_JS = """
    document.querySelectorAll('.lang-switcher, .accessibility-bar, [class*="lang-switch"], [class*="a11y"], .font-size-controls, .font-controls, .accessibility-controls').forEach(el => el.style.display = 'none');
    document.querySelectorAll('button').forEach(b => {
        if (b.textContent.trim() === 'A-' || b.textContent.trim() === 'A+' || b.textContent.trim() === 'EN' || b.textContent.trim() === 'AR' || b.textContent.trim() === 'FR') {
            b.style.display = 'none';
        }
    });
"""

def capture():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            viewport={"width": 440, "height": 956},  # 1320/3, 2868/3
            device_scale_factor=3,
            user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            is_mobile=True,
        )
        page = context.new_page()

        # Landing page sections
        page.goto(f"{BASE_URL}/", wait_until="networkidle", timeout=30000)
        time.sleep(3)
        page.evaluate(HIDE_CONTROLS_JS)

        # main
        page.evaluate("window.scrollTo(0, 0)")
        time.sleep(0.5)
        page.screenshot(path=os.path.join(OUTPUT_DIR, "main.png"))
        print("  main ✓")

        # features
        page.evaluate("const el = document.querySelector('#features') || document.querySelector('section:nth-of-type(2)'); if (el) el.scrollIntoView({ behavior: 'instant', block: 'start' });")
        time.sleep(1)
        page.screenshot(path=os.path.join(OUTPUT_DIR, "features.png"))
        print("  features ✓")

        # howitworks
        page.evaluate("const el = document.querySelector('#how') || document.querySelector('[id*=\"how\"]'); if (el) el.scrollIntoView({ behavior: 'instant', block: 'start' }); else window.scrollTo(0, document.body.scrollHeight * 0.40);")
        time.sleep(1)
        page.screenshot(path=os.path.join(OUTPUT_DIR, "howitworks.png"))
        print("  howitworks ✓")

        # testimonials
        page.evaluate("""
            const headings = document.querySelectorAll('h2, h3');
            for (const h of headings) {
                if (h.textContent.includes('Users Say') || h.textContent.includes('Testimonial')) {
                    h.scrollIntoView({ behavior: 'instant', block: 'start' });
                    break;
                }
            }
        """)
        time.sleep(1)
        page.screenshot(path=os.path.join(OUTPUT_DIR, "testimonials.png"))
        print("  testimonials ✓")

        # login
        page.goto(f"{BASE_URL}/login.php", wait_until="networkidle", timeout=30000)
        time.sleep(2)
        page.screenshot(path=os.path.join(OUTPUT_DIR, "login.png"))
        print("  login ✓")

        # Demo login
        demo_btn = page.query_selector('a:has-text("Try a Demo"), button:has-text("Try a Demo")')
        if demo_btn:
            demo_btn.click()
            time.sleep(5)
            print(f"  Logged in: {page.url}")

            # dashboard
            page.screenshot(path=os.path.join(OUTPUT_DIR, "dashboard.png"))
            print("  dashboard ✓")

            # chat
            page.evaluate("""
                const links = document.querySelectorAll('nav a, .bottom-nav a, .tab-bar a, a');
                for (const a of links) {
                    if (a.textContent.trim() === 'Chat' || a.href?.includes('chat')) { a.click(); break; }
                }
            """)
            time.sleep(3)
            page.screenshot(path=os.path.join(OUTPUT_DIR, "chat.png"))
            print("  chat ✓")

            # meals/diary
            page.evaluate("""
                const links = document.querySelectorAll('nav a, .bottom-nav a, a');
                for (const a of links) {
                    if (a.textContent.trim() === 'Diary' || a.textContent.trim() === 'Meals') { a.click(); break; }
                }
            """)
            time.sleep(3)
            page.screenshot(path=os.path.join(OUTPUT_DIR, "meals.png"))
            print("  meals ✓")

            # history/progress
            page.evaluate("""
                const links = document.querySelectorAll('nav a, .bottom-nav a, a');
                for (const a of links) {
                    if (a.textContent.trim() === 'Progress' || a.textContent.trim() === 'History') { a.click(); break; }
                }
            """)
            time.sleep(3)
            page.screenshot(path=os.path.join(OUTPUT_DIR, "history.png"))
            print("  history ✓")

            # settings
            page.goto(f"{BASE_URL}/settings.php", wait_until="networkidle", timeout=30000)
            time.sleep(3)
            page.screenshot(path=os.path.join(OUTPUT_DIR, "settings.png"))
            print("  settings ✓")

        browser.close()
    print("Done!")

if __name__ == "__main__":
    capture()
