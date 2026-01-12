import os
from tkinter import messagebox
import base64
from io import BytesIO
from PIL import Image, ImageTk
from .config import REFRESH_ICON_BASE64


def has_full_disk_access():
    """Checks for Full Disk Access by trying to list a protected directory."""
    protected_dir = os.path.expanduser(
        '~/Library/Application Support/com.apple.TCC/')
    try:
        os.listdir(protected_dir)
        print("Full Disk Access check: Succeeded.")
        return True
    except PermissionError:
        print("Full Disk Access check: Failed (PermissionError).")
        return False
    except FileNotFoundError:
        print("Full Disk Access check: TCC directory not found, cannot determine access.")
        return True
    except Exception as e:
        print(f"Full Disk Access check: An unexpected error occurred: {e}")
        return True


def prompt_for_full_disk_access():
    """Shows a dialog to guide the user to grant Full Disk Access."""
    message = (
        "FnMacAssistant may require Full Disk Access to find the Fortnite container.\n\n"
        "To grant permission:\n"
        "1. Open System Settings > Privacy & Security.\n"
        "2. Scroll down and click on 'Full Disk Access'.\n"
        "3. Click the '+' button and add FnMacAssistant.\n"
        "4. If the app is already in the list, make sure it is enabled.\n\n"
        "Please grant access and restart the application.")
    messagebox.showwarning("Full Disk Access Required", message)


def load_refresh_icon():
    try:
        icon_data = base64.b64decode(REFRESH_ICON_BASE64)
        image = Image.open(BytesIO(icon_data))
        image = image.resize((24, 24), Image.Resampling.LANCZOS)
        return ImageTk.PhotoImage(image)
    except Exception as e:
        print(f"Failed to load refresh icon: {str(e)}")
        return None
