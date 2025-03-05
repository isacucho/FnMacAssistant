import os
import requests
import shutil
import tkinter as tk
from tkinter import messagebox, ttk
import threading
import base64
from io import BytesIO
from PIL import Image, ImageTk

GIST_ID = "fb6a16acae4e592603540249cbb7e08d"
GIST_API_URL = f"https://api.github.com/gists/{GIST_ID}"

# Corrected base64-encoded 16x16 refresh icon (GIF)
REFRESH_ICON_BASE64 = """
R0lGODlhEAAQAMQAAO/v7+zs7OLg4N/f3+Li4uDg4N3d3ejo6OHh4d7e3ubm5t3d3eHh4d/f39/f
3+Dg4OHh4ejo6N3d3d7e3uLi4t3d3eDg4OHh4ejo6N3d3eHh4d7e3uDg4OHh4ejo6N3d3eHh4QAA
ACH5BAEAABwALAAAAAAQABAAAAVRYCSOZGl+ZQpCZJrvqTQiVq7vdYJgsDofD8SYJCKfT0fEQPD9
fYCFEQzQeB5oOgoRUKjdbrfcrnY7nZ7P63O4XGy3u2y1u8PhcLi7XC6Hw+Hw+n0BFiYBLCMhIQA7
"""

def get_latest_raw_url():
    try:
        headers = {"Accept": "application/vnd.github.v3+json"}
        response = requests.get(GIST_API_URL, headers=headers, timeout=10)
        response.raise_for_status()
        gist_data = response.json()
        raw_url = gist_data["files"]["list.json"]["raw_url"]
        print("Latest raw URL:", raw_url)
        return raw_url
    except Exception as e:
        messagebox.showerror("Error", f"Failed to fetch Gist metadata: {str(e)}")
        return None

def get_file_size(url):
    try:
        response = requests.head(url, timeout=10, allow_redirects=True)
        if response.status_code == 200 and 'Content-Length' in response.headers:
            return int(response.headers['Content-Length'])
    except requests.RequestException:
        pass

    try:
        response = requests.get(url, stream=True, timeout=10)
        response.raise_for_status()
        if 'Content-Length' in response.headers:
            return int(response.headers['Content-Length'])
        return None
    except requests.RequestException as e:
        print(f"Failed to fetch size for {url}: {str(e)}")
        return None

def get_ipa_data():
    try:
        raw_url = get_latest_raw_url()
        if not raw_url:
            return []
        
        headers = {
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Pragma": "no-cache",
            "Expires": "0"
        }
        with requests.Session() as session:
            response = session.get(raw_url, headers=headers, timeout=10)
            response.raise_for_status()

            print("Fetching from:", raw_url)
            print("Raw JSON:", response.text)

            ipa_data = response.json()
            ipa_files = []
            for item in ipa_data:
                if all(k in item for k in ['name', 'download_url']):
                    size = get_file_size(item['download_url'])
                    if size is None and 'size' in item:
                        size = item['size']
                    ipa_files.append({
                        'name': item['name'],
                        'browser_download_url': item['download_url'],
                        'size': size if size is not None else 0
                    })
            print("Parsed ipa_files:", ipa_files)
            return ipa_files
    except requests.exceptions.RequestException as e:
        messagebox.showerror("Error", f"Network error: {str(e)}")
        return []
    except ValueError as e:
        messagebox.showerror("Error", f"JSON error: {str(e)}\nRaw response: {response.text}")
        return []

def download_ipa(selected_ipa_url, selected_ipa_name, file_size):
    download_path = os.path.expanduser(f"~/Downloads/{selected_ipa_name}")
    progress_bar.pack(pady=10)
    progress_label.pack(pady=10)
    progress_var.set(0)
    root.update()

    try:
        response = requests.get(selected_ipa_url, stream=True)
        response.raise_for_status()
        downloaded_size = 0
        chunk_size = 8192
        with open(download_path, 'wb') as ipa_file:
            for chunk in response.iter_content(chunk_size=chunk_size):
                if chunk:
                    ipa_file.write(chunk)
                    downloaded_size += len(chunk)
                    if file_size > 0:
                        percentage = (downloaded_size / file_size) * 100
                        progress_var.set(percentage)
                        mb_downloaded = downloaded_size / (1024 * 1024)
                        total_mb = file_size / (1024 * 1024)
                        progress_label.config(text=f"Downloaded {mb_downloaded:.2f} MB of {total_mb:.2f} MB")
                    else:
                        mb_downloaded = downloaded_size / (1024 * 1024)
                        progress_label.config(text=f"Downloaded {mb_downloaded:.2f} MB (size unknown)")
                    root.update_idletasks()
        message = (
            "Download completed!\n\n"
            "Proceed with the app installation, open the game and make sure it crashes, then return here and patch."
        )
        messagebox.showinfo("Download Complete", message)
    except Exception as e:
        messagebox.showerror("Error", f"Failed to download the file: {str(e)}")

def start_download():
    selected_ipa = ipa_combobox.get()
    if selected_ipa and selected_ipa in ipa_files_dict:
        selected_ipa_data = ipa_files_dict[selected_ipa]
        selected_ipa_url = selected_ipa_data['browser_download_url']
        selected_ipa_name = selected_ipa_data['name']
        file_size = selected_ipa_data['size']
        download_thread = threading.Thread(target=download_ipa, args=(selected_ipa_url, selected_ipa_name, file_size))
        download_thread.start()
    else:
        messagebox.showerror("Error", "Please select a valid file.")

def populate_ipa_dropdown():
    global ipa_files_dict
    print("Starting dropdown refresh...")
    ipa_files_dict = {}
    ipa_files = get_ipa_data()
    if ipa_files:
        ipa_files_dict = {file['name']: file for file in ipa_files}
        print("New ipa_files_dict:", ipa_files_dict)
        print("Updating Combobox with values:", list(ipa_files_dict.keys()))
        
        ipa_combobox['values'] = []
        ipa_combobox.delete(0, tk.END)
        ipa_combobox['values'] = list(ipa_files_dict.keys())
        if ipa_files_dict:
            ipa_combobox.current(0)
        else:
            ipa_combobox.set("No files available")
        root.update_idletasks()
        print("Dropdown updated.")
    else:
        ipa_combobox['values'] = []
        ipa_combobox.delete(0, tk.END)
        ipa_combobox.set("No files available")
        root.update_idletasks()
        print("Dropdown set to empty.")

def refresh_dropdown():
    print("Refresh button clicked.")
    populate_ipa_dropdown()
    messagebox.showinfo("Refresh", "File list refreshed.")

def patch_app():
    provision_url = "https://github.com/isacucho/FnMacAssistant/raw/main/files/embedded.mobileprovision"
    temp_path = "/tmp/embedded.mobileprovision"
    fortnite_app_path = "/Applications/Fortnite.app"
    fortnite_1_app_path = "/Applications/Fortnite-1.app"
    provision_dest_path = os.path.join(fortnite_app_path, "Wrapper/FortniteClient-IOS-Shipping.app/embedded.mobileprovision")

    try:
        response = requests.get(provision_url, stream=True)
        response.raise_for_status()
        with open(temp_path, 'wb') as provision_file:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    provision_file.write(chunk)
        if os.path.exists(fortnite_1_app_path):
            if os.path.exists(fortnite_app_path):
                shutil.rmtree(fortnite_app_path)
            os.rename(fortnite_1_app_path, fortnite_app_path)
        if not os.path.exists(os.path.dirname(provision_dest_path)):
            os.makedirs(os.path.dirname(provision_dest_path))
        shutil.move(temp_path, provision_dest_path)
        messagebox.showinfo("Patch Complete", "Fortnite has been patched. You can now open Fortnite.")
    except Exception as e:
        messagebox.showerror("Error", f"Failed to patch the app: {str(e)}")

def load_refresh_icon():
    try:
        icon_data = base64.b64decode(REFRESH_ICON_BASE64)
        image = Image.open(BytesIO(icon_data))
        image = image.resize((24, 24), Image.Resampling.LANCZOS)
        return ImageTk.PhotoImage(image)
    except Exception as e:
        print(f"Failed to load refresh icon: {str(e)}")
        return None

root = tk.Tk()
root.lift()
root.focus_force()
root.title("FnMacAssistant")
root.geometry("500x350")

top_frame = tk.Frame(root)
top_frame.pack(pady=5)

ipa_combobox_label = tk.Label(top_frame, text="Select file to download:")
ipa_combobox_label.pack(pady=5)

dropdown_frame = tk.Frame(top_frame)
dropdown_frame.pack()

ipa_combobox = ttk.Combobox(dropdown_frame, width=40)
ipa_combobox.pack(side=tk.LEFT, padx=(0, 10))

refresh_icon = load_refresh_icon()
if refresh_icon:
    refresh_button = tk.Button(dropdown_frame, image=refresh_icon, command=refresh_dropdown, 
                              width=24, height=24, borderwidth=0, padx=0, pady=0)
else:
    refresh_button = tk.Button(dropdown_frame, text="↻", command=refresh_dropdown, width=1, height=1)
refresh_button.pack(side=tk.LEFT)

ipa_files_dict = {}
populate_ipa_dropdown()

download_button = tk.Button(root, text="Download File", command=start_download, width=40, height=2)
download_button.pack(pady=20)

patch_button = tk.Button(root, text="Patch App", command=patch_app, width=40, height=2)
patch_button.pack(pady=20)

progress_var = tk.DoubleVar()
progress_bar = ttk.Progressbar(root, variable=progress_var, maximum=100, length=400)
progress_label = tk.Label(root, text="")

root.mainloop()
