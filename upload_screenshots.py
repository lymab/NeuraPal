#!/usr/bin/env python3
"""Upload screenshots to App Store Connect via API directly."""

import jwt
import time
import json
import hashlib
import os
import urllib.request
import urllib.error

API_KEY_PATH = os.path.expanduser("~/.appstoreconnect/api_key.json")
APP_ID = "6759394632"
VERSION_ID = "7dbbef3b-3e32-47ae-96d1-3757807bf220"  # Version 2.1
SCREENSHOT_DIR = "/Users/lyaz/neurapal-ios/new-screenshots"

# App Store Connect screenshot display types
DISPLAY_TYPES = {
    "iphone69": "APP_IPHONE_69",      # 6.9" - 1320x2868
    "iphone67": "APP_IPHONE_67",      # 6.7" - 1290x2796
    "iphone65": "APP_IPHONE_65",      # 6.5" - 1242x2688
    "ipad_pro_129": "APP_IPAD_PRO_129",         # iPad Pro 12.9"
    "ipad_pro_3gen_129": "APP_IPAD_PRO_3GEN_129",  # iPad Pro 3rd Gen 12.9"
}

SCREENS = ["main", "features", "howitworks", "testimonials", "login",
           "dashboard", "chat", "meals", "history", "settings"]


def get_token():
    with open(API_KEY_PATH) as f:
        api_key = json.load(f)
    now = int(time.time())
    payload = {"iss": api_key["issuer_id"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, api_key["key"], algorithm="ES256",
                      headers={"alg": "ES256", "kid": api_key["key_id"], "typ": "JWT"})


def api_request(url, method="GET", data=None, token=None, content_type="application/json"):
    headers = {"Authorization": f"Bearer {token}", "Content-Type": content_type}
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read()) if resp.status != 204 else None
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        print(f"  API Error {e.code}: {error_body[:500]}")
        return None


def get_localizations(token):
    """Get app store version localizations."""
    url = f"https://api.appstoreconnect.apple.com/v1/appStoreVersions/{VERSION_ID}/appStoreVersionLocalizations"
    result = api_request(url, token=token)
    if result:
        for loc in result["data"]:
            if loc["attributes"]["locale"] == "en-US":
                return loc["id"]
    return None


def get_screenshot_sets(localization_id, token):
    """Get existing screenshot sets for a localization."""
    url = f"https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets"
    result = api_request(url, token=token)
    return result["data"] if result else []


def delete_screenshot(screenshot_id, token):
    """Delete a single screenshot."""
    url = f"https://api.appstoreconnect.apple.com/v1/appScreenshots/{screenshot_id}"
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}"
    }, method="DELETE")
    try:
        urllib.request.urlopen(req)
        return True
    except urllib.error.HTTPError as e:
        print(f"  Delete error: {e.code}")
        return False


def delete_screenshot_set(set_id, token):
    """Delete a screenshot set."""
    url = f"https://api.appstoreconnect.apple.com/v1/appScreenshotSets/{set_id}"
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}"
    }, method="DELETE")
    try:
        urllib.request.urlopen(req)
        return True
    except urllib.error.HTTPError as e:
        print(f"  Delete set error: {e.code}")
        return False


def create_screenshot_set(localization_id, display_type, token):
    """Create a new screenshot set for a display type."""
    url = "https://api.appstoreconnect.apple.com/v1/appScreenshotSets"
    data = {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {
                "screenshotDisplayType": display_type
            },
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "id": localization_id
                    }
                }
            }
        }
    }
    result = api_request(url, method="POST", data=data, token=token)
    if result:
        return result["data"]["id"]
    return None


def upload_screenshot(set_id, filepath, token):
    """Upload a screenshot to a screenshot set using the 3-step process."""
    filename = os.path.basename(filepath)
    filesize = os.path.getsize(filepath)

    # Step 1: Reserve the screenshot
    with open(filepath, "rb") as f:
        file_data = f.read()
    checksum = hashlib.md5(file_data).hexdigest()

    reserve_data = {
        "data": {
            "type": "appScreenshots",
            "attributes": {
                "fileName": filename,
                "fileSize": filesize
            },
            "relationships": {
                "appScreenshotSet": {
                    "data": {
                        "type": "appScreenshotSets",
                        "id": set_id
                    }
                }
            }
        }
    }

    result = api_request(
        "https://api.appstoreconnect.apple.com/v1/appScreenshots",
        method="POST", data=reserve_data, token=token
    )
    if not result:
        return False

    screenshot_id = result["data"]["id"]
    upload_ops = result["data"]["attributes"].get("uploadOperations", [])

    # Step 2: Upload the file parts
    for op in upload_ops:
        url = op["url"]
        offset = op["offset"]
        length = op["length"]
        chunk = file_data[offset:offset + length]

        headers_list = {h["name"]: h["value"] for h in op["requestHeaders"]}

        req = urllib.request.Request(url, data=chunk, headers=headers_list, method="PUT")
        try:
            urllib.request.urlopen(req)
        except urllib.error.HTTPError as e:
            print(f"  Upload chunk error: {e.code}")
            return False

    # Step 3: Commit the upload
    commit_data = {
        "data": {
            "type": "appScreenshots",
            "id": screenshot_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": checksum
            }
        }
    }

    result = api_request(
        f"https://api.appstoreconnect.apple.com/v1/appScreenshots/{screenshot_id}",
        method="PATCH", data=commit_data, token=token
    )
    return result is not None


def main():
    token = get_token()

    # Get localization ID
    print("Getting en-US localization...")
    loc_id = get_localizations(token)
    if not loc_id:
        print("ERROR: Could not find en-US localization")
        return
    print(f"  Localization ID: {loc_id}")

    # Get existing screenshot sets and delete them
    print("\nDeleting existing screenshot sets...")
    existing_sets = get_screenshot_sets(loc_id, token)
    for ss_set in existing_sets:
        display_type = ss_set["attributes"]["screenshotDisplayType"]
        set_id = ss_set["id"]
        print(f"  Deleting set {display_type}...")

        # First get and delete individual screenshots in this set
        screenshots_url = f"https://api.appstoreconnect.apple.com/v1/appScreenshotSets/{set_id}/appScreenshots"
        screenshots = api_request(screenshots_url, token=token)
        if screenshots and screenshots.get("data"):
            for ss in screenshots["data"]:
                delete_screenshot(ss["id"], token)

        # Then delete the set itself
        delete_screenshot_set(set_id, token)
        time.sleep(0.5)

    # Upload new screenshots
    print("\nUploading new screenshots...")
    for device_dir, display_type in DISPLAY_TYPES.items():
        dir_path = os.path.join(SCREENSHOT_DIR, device_dir)
        if not os.path.exists(dir_path):
            print(f"  Skipping {device_dir} - directory not found")
            continue

        print(f"\n  Creating set for {display_type}...")
        token = get_token()  # Refresh token
        set_id = create_screenshot_set(loc_id, display_type, token)
        if not set_id:
            print(f"  ERROR: Could not create screenshot set for {display_type}")
            continue
        print(f"  Set ID: {set_id}")

        for screen in SCREENS:
            filepath = os.path.join(dir_path, f"{screen}.png")
            if not os.path.exists(filepath):
                print(f"    {screen} - SKIPPED (not found)")
                continue

            print(f"    Uploading {screen}...", end=" ", flush=True)
            success = upload_screenshot(set_id, filepath, token)
            print("✓" if success else "FAILED")
            time.sleep(1)  # Rate limiting

    print("\n=== Upload complete! ===")


if __name__ == "__main__":
    main()
