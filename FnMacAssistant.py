import os
import requests
import shutil
import tkinter as tk
from tkinter import messagebox, ttk
import threading

# Function to get the latest release assets from GitHub and file size
def get_latest_release_assets():
    api_url = "https://api.github.com/repos/isacucho/FnMacIPAs/releases/latest"
    try:
        response = requests.get(api_url)
        response.raise_for_status()

        release_data = response.json()
        # Get all .ipa assets along with their sizes
        ipa_files = [
            {
                'name': asset['name'],
                'browser_download_url': asset['browser_download_url'],
                'size': asset['size']  # size in bytes from the API
            }
            for asset in release_data.get('assets', [])
            if asset['name'].endswith('.ipa')
        ]
        return ipa_files
    except Exception as e:
        messagebox.showerror("Error", f"Failed to fetch latest release assets: {str(e)}")
        return []

# Function to download the selected IPA file with progress bar
def download_ipa(selected_ipa_url, selected_ipa_name, file_size):
    download_path = os.path.expanduser(f"~/Downloads/{selected_ipa_name}")

    # Show the progress bar and label when the download starts
    progress_bar.pack(pady=10)
    progress_label.pack(pady=10)
    progress_var.set(0)

    # Force the GUI to update immediately to show the progress bar and label
    root.update()

    try:
        # Stream the file in chunks and update the progress bar
        response = requests.get(selected_ipa_url, stream=True)
        response.raise_for_status()

        # Progress tracking variables
        downloaded_size = 0
        chunk_size = 8192  # 8 KB

        with open(download_path, 'wb') as ipa_file:
            for chunk in response.iter_content(chunk_size=chunk_size):
                if chunk:
                    ipa_file.write(chunk)
                    downloaded_size += len(chunk)

                    # Update the progress bar and label using the actual file size
                    percentage = (downloaded_size / file_size) * 100
                    progress_var.set(percentage)

                    # Update the label with MB downloaded
                    mb_downloaded = downloaded_size / (1024 * 1024)  # Convert to MB
                    total_mb = file_size / (1024 * 1024)
                    progress_label.config(text=f"Downloaded {mb_downloaded:.2f} MB of {total_mb:.2f} MB")

                    # Force the GUI to update during the download
                    root.update_idletasks()

        # Show success message with reminders
        message = (
            f"{selected_ipa_name} was downloaded to your Downloads folder.\n\n"
            "Please sideload it using Sideloadly, then return to the asisstant to patch the app.\n\n"
            "Remember: You will need to sideload and patch the game every 7 days."
        )
        messagebox.showinfo("Download Complete", message)
    except Exception as e:
        messagebox.showerror("Error", f"Failed to download the IPA: {str(e)}")

# Function to start the download in a separate thread
def start_download():
    selected_ipa = ipa_combobox.get()
    if selected_ipa and selected_ipa in ipa_files_dict:
        selected_ipa_data = ipa_files_dict[selected_ipa]
        selected_ipa_url = selected_ipa_data['browser_download_url']
        selected_ipa_name = selected_ipa_data['name']
        file_size = selected_ipa_data['size']  # File size in bytes
        download_thread = threading.Thread(target=download_ipa, args=(selected_ipa_url, selected_ipa_name, file_size))
        download_thread.start()
    else:
        messagebox.showerror("Error", "Please select a valid IPA file.")

# Function to populate the dropdown with available IPA files
def populate_ipa_dropdown():
    ipa_files = get_latest_release_assets()
    if ipa_files:
        global ipa_files_dict
        ipa_files_dict = {file['name']: file for file in ipa_files}
        ipa_combobox['values'] = list(ipa_files_dict.keys())
        ipa_combobox.current(0)  # Set the default selection to the first IPA file

# Function to patch the app (no changes here)
def patch_app():
    provision_url = "https://github.com/isacucho/FnMacAssistant/raw/main/files/embedded.mobileprovision"
    temp_path = "/tmp/embedded.mobileprovision"
    fortnite_app_path = "/Applications/Fortnite.app"
    fortnite_1_app_path = "/Applications/Fortnite-1.app"
    provision_dest_path = os.path.join(fortnite_app_path, "Wrapper/FortniteClient-IOS-Shipping.app/embedded.mobileprovision")

    try:
        # Step 1: Download the embedded.mobileprovision file
        response = requests.get(provision_url, stream=True)
        response.raise_for_status()

        # Save the mobileprovision file temporarily
        with open(temp_path, 'wb') as provision_file:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    provision_file.write(chunk)

        # Step 2: Check if Fortnite-1.app exists
        if os.path.exists(fortnite_1_app_path):
            # Delete Fortnite.app if it exists
            if os.path.exists(fortnite_app_path):
                shutil.rmtree(fortnite_app_path)

            # Rename Fortnite-1.app to Fortnite.app
            os.rename(fortnite_1_app_path, fortnite_app_path)

        # Step 3: Move the mobileprovision file to the correct location
        if not os.path.exists(os.path.dirname(provision_dest_path)):
            os.makedirs(os.path.dirname(provision_dest_path))

        shutil.move(temp_path, provision_dest_path)

        # Show success message
        messagebox.showinfo("Patch Complete", "Fortnite has been patched. You can now open Fortnite.")
    except Exception as e:
        messagebox.showerror("Error", f"Failed to patch the app: {str(e)}")

# Create the main application window
root = tk.Tk()
root.lift()
root.focus_force()
root.title("FnMacAssistant")
root.geometry("500x350")  # Adjust the window size

# Create the IPA selection dropdown (combobox)
ipa_combobox_label = tk.Label(root, text="Select IPA to download:")
ipa_combobox_label.pack(pady=5)
ipa_combobox = ttk.Combobox(root, width=40)
ipa_combobox.pack(pady=10)

# Populate the IPA dropdown with the latest release assets
populate_ipa_dropdown()

# Create the Download IPA button
download_button = tk.Button(root, text="Download IPA", command=start_download, width=40, height=2)
download_button.pack(pady=20)

# Create the Patch App button
patch_button = tk.Button(root, text="Patch App", command=patch_app, width=40, height=2)
patch_button.pack(pady=20)

# Create the progress bar (it will be hidden initially)
progress_var = tk.DoubleVar()
progress_bar = ttk.Progressbar(root, variable=progress_var, maximum=100, length=400)

# Create a label for displaying the download progress (hidden initially)
progress_label = tk.Label(root, text="")

# Start the main loop
root.mainloop()
