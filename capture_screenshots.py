#!/usr/bin/env python3
"""Capture Sadiky App Store screenshots at exact device resolutions."""

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

HIDE_CONTROLS_JS = """
    document.querySelectorAll('.lang-switcher, .accessibility-bar, [class*="lang-switch"], [class*="a11y"], .font-size-controls, .font-controls, .accessibility-controls').forEach(el => el.style.display = 'none');
    // Also hide the A-/A+ buttons
    document.querySelectorAll('button').forEach(b => {
        if (b.textContent.trim() === 'A-' || b.textContent.trim() === 'A+' || b.textContent.trim() === 'EN' || b.textContent.trim() === 'AR' || b.textContent.trim() === 'FR') {
            b.style.display = 'none';
        }
    });
"""


def capture_landing_sections(page, device_dir, device_name):
    """Capture sections of the landing page by scrolling."""
    page.goto(f"{BASE_URL}/", wait_until="networkidle", timeout=30000)
    time.sleep(3)
    page.evaluate(HIDE_CONTROLS_JS)
    time.sleep(0.5)

    # 1. main — top of page
    page.evaluate("window.scrollTo(0, 0)")
    time.sleep(0.5)
    page.screenshot(path=os.path.join(device_dir, "main.png"))
    print(f"    main ✓")

    # 2. features — scroll to #features section
    page.evaluate("""
        const el = document.querySelector('#features') || document.querySelector('section:nth-of-type(2)');
        if (el) el.scrollIntoView({ behavior: 'instant', block: 'start' });
    """)
    time.sleep(1)
    page.screenshot(path=os.path.join(device_dir, "features.png"))
    print(f"    features ✓")

    # 3. howitworks — scroll to #how section
    page.evaluate("""
        const el = document.querySelector('#how') || document.querySelector('[id*="how"]');
        if (el) { el.scrollIntoView({ behavior: 'instant', block: 'start' }); }
        else { window.scrollTo(0, document.body.scrollHeight * 0.40); }
    """)
    time.sleep(1)
    page.screenshot(path=os.path.join(device_dir, "howitworks.png"))
    print(f"    howitworks ✓")

    # 4. testimonials — look for testimonial/review section
    page.evaluate("""
        const el = document.querySelector('#testimonials') ||
                   document.querySelector('[id*="testimonial"]') ||
                   document.querySelector('[id*="review"]');
        if (el) { el.scrollIntoView({ behavior: 'instant', block: 'start' }); }
        else {
            // Find heading containing "Users Say" or "Testimonials"
            const headings = document.querySelectorAll('h2, h3');
            for (const h of headings) {
                if (h.textContent.includes('Users Say') || h.textContent.includes('Testimonial') || h.textContent.includes('Review')) {
                    h.scrollIntoView({ behavior: 'instant', block: 'start' });
                    break;
                }
            }
        }
    """)
    time.sleep(1)
    page.screenshot(path=os.path.join(device_dir, "testimonials.png"))
    print(f"    testimonials ✓")

    # 5. cta — bottom section with signup CTA
    page.evaluate("""
        const headings = document.querySelectorAll('h2, h3');
        let found = false;
        for (const h of headings) {
            if (h.textContent.includes('Create') || h.textContent.includes('Get Started') || h.textContent.includes('Ready')) {
                h.scrollIntoView({ behavior: 'instant', block: 'center' });
                found = true;
                break;
            }
        }
        if (!found) {
            window.scrollTo(0, document.body.scrollHeight - window.innerHeight);
        }
    """)
    time.sleep(1)
    page.screenshot(path=os.path.join(device_dir, "cta.png"))
    print(f"    cta ✓")


def capture_login(page, device_dir):
    """Capture login page."""
    page.goto(f"{BASE_URL}/login.php", wait_until="networkidle", timeout=30000)
    time.sleep(2)
    page.screenshot(path=os.path.join(device_dir, "login.png"))
    print(f"    login ✓")


def capture_consent(page, device_dir):
    """Capture privacy/consent page."""
    page.goto(f"{BASE_URL}/privacy.php", wait_until="networkidle", timeout=30000)
    time.sleep(2)
    page.screenshot(path=os.path.join(device_dir, "consent.png"))
    print(f"    consent ✓")


def login_demo(page):
    """Login with demo account."""
    page.goto(f"{BASE_URL}/login.php", wait_until="networkidle", timeout=30000)
    time.sleep(2)

    # Click "Try a Demo" button
    demo_btn = page.query_selector('a:has-text("Try a Demo"), button:has-text("Try a Demo"), a:has-text("Try Demo"), button:has-text("Try Demo")')
    if demo_btn:
        demo_btn.click()
        time.sleep(5)
        print(f"    Demo login successful, URL: {page.url}")
        return True
    else:
        print(f"    No demo button found!")
        return False


def capture_logged_in_screens(page, device_dir, is_mobile):
    """Capture screens by clicking bottom nav tabs in the SPA."""

    # After demo login, we should be on dashboard.php
    # Take dashboard screenshot first
    time.sleep(2)
    page.screenshot(path=os.path.join(device_dir, "dashboard.png"))
    print(f"    dashboard ✓")

    # The bottom nav has tabs - let's find and click them
    # Based on settings screenshot: Progress, Diary, Chat, Plans, Recipes

    # Chat tab
    try:
        chat_tab = page.query_selector('a[href*="chat"], nav a:has-text("Chat"), .nav-item:has-text("Chat"), [data-tab="chat"]')
        if chat_tab:
            chat_tab.click()
            time.sleep(3)
        else:
            # Try clicking by text in bottom nav
            page.evaluate("""
                const links = document.querySelectorAll('nav a, .bottom-nav a, .tab-bar a, footer a');
                for (const a of links) {
                    if (a.textContent.trim() === 'Chat' || a.href.includes('chat')) {
                        a.click(); break;
                    }
                }
            """)
            time.sleep(3)
        page.screenshot(path=os.path.join(device_dir, "chat.png"))
        print(f"    chat ✓")
    except Exception as e:
        print(f"    chat ERROR: {e}")
        # Use dashboard as fallback for chat
        page.screenshot(path=os.path.join(device_dir, "chat.png"))
        print(f"    chat (fallback to dashboard) ✓")

    # Meals/Diary tab
    try:
        page.evaluate("""
            const links = document.querySelectorAll('nav a, .bottom-nav a, .tab-bar a, a');
            for (const a of links) {
                if (a.textContent.trim() === 'Diary' || a.textContent.trim() === 'Meals' ||
                    a.href?.includes('diary') || a.href?.includes('meals') || a.href?.includes('recipes')) {
                    a.click(); break;
                }
            }
        """)
        time.sleep(3)
        page.screenshot(path=os.path.join(device_dir, "meals.png"))
        print(f"    meals ✓")
    except Exception as e:
        print(f"    meals ERROR: {e}")

    # History/Progress tab
    try:
        page.evaluate("""
            const links = document.querySelectorAll('nav a, .bottom-nav a, .tab-bar a, a');
            for (const a of links) {
                if (a.textContent.trim() === 'Progress' || a.textContent.trim() === 'History' ||
                    a.href?.includes('progress') || a.href?.includes('history')) {
                    a.click(); break;
                }
            }
        """)
        time.sleep(3)
        page.screenshot(path=os.path.join(device_dir, "history.png"))
        print(f"    history ✓")
    except Exception as e:
        print(f"    history ERROR: {e}")

    # Settings - click gear icon or settings link
    try:
        page.evaluate("""
            const links = document.querySelectorAll('nav a, .bottom-nav a, .tab-bar a, a, button');
            for (const a of links) {
                if (a.textContent.trim() === 'Settings' || a.href?.includes('settings') ||
                    a.getAttribute('aria-label')?.includes('settings')) {
                    a.click(); break;
                }
            }
        """)
        time.sleep(3)
        # Check if we're on settings, if not try the gear icon
        if 'settings' not in page.url.lower():
            page.evaluate("""
                const icons = document.querySelectorAll('[class*="settings"], [class*="gear"], svg');
                for (const icon of icons) {
                    const parent = icon.closest('a, button');
                    if (parent) { parent.click(); break; }
                }
            """)
            time.sleep(3)
        page.screenshot(path=os.path.join(device_dir, "settings.png"))
        print(f"    settings ✓")
    except Exception as e:
        print(f"    settings ERROR: {e}")


def capture_screenshots():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    with sync_playwright() as p:
        for device_name, device_config in DEVICES.items():
            device_dir = os.path.join(OUTPUT_DIR, device_name)
            os.makedirs(device_dir, exist_ok=True)

            print(f"\n=== Capturing {device_name} ({device_config['viewport']['width']}x{device_config['viewport']['height']} @{device_config['device_scale_factor']}x) ===")

            browser = p.chromium.launch(headless=True)
            context = browser.new_context(
                viewport=device_config["viewport"],
                device_scale_factor=device_config["device_scale_factor"],
                user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1" if device_config["is_mobile"] else "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                is_mobile=device_config["is_mobile"],
            )

            page = context.new_page()

            # Landing page sections
            print("  Landing page sections:")
            capture_landing_sections(page, device_dir, device_name)

            # Login page
            print("  Auth pages:")
            capture_login(page, device_dir)

            # Consent/privacy page
            capture_consent(page, device_dir)

            # Logged-in screens
            print("  Logged-in screens:")
            if login_demo(page):
                capture_logged_in_screens(page, device_dir, device_config["is_mobile"])
            else:
                print("    SKIPPED - could not login")

            browser.close()

    print(f"\n=== All screenshots saved to {OUTPUT_DIR} ===")


if __name__ == "__main__":
    capture_screenshots()
