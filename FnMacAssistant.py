import os
import requests
import shutil
import tkinter as tk
from tkinter import messagebox, ttk
import threading
import base64
from io import BytesIO
from PIL import Image, ImageTk
import webbrowser
import subprocess
import time
import plistlib
import zipfile


VERSION = "1.4.1"
GITHUB_RELEASES_URL = "https://api.github.com/repos/isacucho/FnMacAssistant/releases/latest"
GIST_ID = "fb6a16acae4e592603540249cbb7e08d"
GIST_API_URL = f"https://api.github.com/gists/{GIST_ID}"

FORTNITE_APP_PATH = "/Applications/Fortnite.app"

def has_full_disk_access():
    """Checks for Full Disk Access by trying to list a protected directory."""
    protected_dir = os.path.expanduser('~/Library/Application Support/com.apple.TCC/')
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
        "Please grant access and restart the application."
    )
    messagebox.showwarning("Full Disk Access Required", message)

def get_fortnite_container_path():
    try:
        containers_dir = os.path.expanduser("~/Library/Containers")
        if not os.path.exists(containers_dir):
            messagebox.showerror("Error", "Could not find Fortnite's container. Make sure to open Fortnite at least once before proceeding.")
            return None
        
        fortnite_containers = []
        fallback_containers = []
        
        for container_name in os.listdir(containers_dir):
            container_path = os.path.join(containers_dir, container_name)
            metadata_path = os.path.join(container_path, ".com.apple.containermanagerd.metadata.plist")
            
            if os.path.exists(metadata_path):
                try:
                    with open(metadata_path, 'rb') as f:
                        metadata = plistlib.load(f)
                        bundle_id = metadata.get('MCMMetadataIdentifier', '').lower()
                        if bundle_id and 'fortnite' in bundle_id:
                            print(f"Found Fortnite container through bundle ID: {container_path}")
                            print(f"Bundle ID: {bundle_id}")
                            fortnite_containers.append(container_path)
                        else:
                            metadata_str = str(metadata).lower()
                            if 'fortnite' in metadata_str:
                                print(f"Found Fortnite container through metadata search: {container_path}")
                                fortnite_containers.append(container_path)
                except Exception as e:
                    print(f"Error reading metadata for {container_path}: {str(e)}")
                    continue
            
            fortnite_game_path = os.path.join(container_path, "Data/Documents/FortniteGame")
            if os.path.exists(fortnite_game_path):
                print(f"Found FortniteGame directory in container: {container_path}")
                fallback_containers.append(container_path)
        
        if not fortnite_containers and fallback_containers:
            print("Using fallback container detection method...")
            fortnite_containers = fallback_containers
        
        if not fortnite_containers:
            print("No Fortnite containers found through any method")
            if not has_full_disk_access():
                prompt_for_full_disk_access()
                return None
            
            messagebox.showerror("Error", "Could not find Fortnite's container. Make sure to open Fortnite at least once before proceeding.")
            return None
        
        if len(fortnite_containers) == 1:
            container_path = fortnite_containers[0]
            fortnite_game_path = os.path.join(container_path, "Data/Documents/FortniteGame")
            if os.path.exists(fortnite_game_path):
                return fortnite_game_path
            else:
                return container_path
        
        else:
            return ask_user_to_choose_container(fortnite_containers)
            
    except Exception as e:
        print(f"Error getting Fortnite container path: {str(e)}")
        messagebox.showerror("Error", "Could not find Fortnite's container. Make sure to open Fortnite at least once before proceeding.")
        return None

def ask_user_to_choose_container(containers):
    choice_window = tk.Toplevel()
    choice_window.title("Multiple Fortnite Containers Found")
    choice_window.geometry("500x350")
    choice_window.grab_set()
    
    tk.Label(choice_window, text="Multiple Fortnite containers were found.\nPlease choose the correct one:", 
             justify="center", font=("Arial", 12)).pack(pady=20)
    
    listbox = tk.Listbox(choice_window, width=70, height=8)
    listbox.pack(pady=10, padx=20)
    
    for i, container in enumerate(containers):
        try:
            total_size = 0
            for dirpath, dirnames, filenames in os.walk(container):
                for filename in filenames:
                    filepath = os.path.join(dirpath, filename)
                    if os.path.exists(filepath):
                        total_size += os.path.getsize(filepath)
            size_mb = total_size / (1024 * 1024)
            display_text = f"{os.path.basename(container)} ({size_mb:.1f} MB)"
        except:
            display_text = os.path.basename(container)
        
        listbox.insert(i, display_text)
    
    listbox.containers = containers
    
    tk.Label(choice_window, text="Tip: The largest container is usually the main one.", 
             font=("Arial", 10), fg="white").pack(pady=5)
    
    button_frame = tk.Frame(choice_window)
    button_frame.pack(pady=20)
    
    result = [None]
    
    def on_select():
        selection = listbox.curselection()
        if selection:
            selected_container = listbox.containers[selection[0]]
            result[0] = selected_container
            choice_window.destroy()
        else:
            messagebox.showwarning("No Selection", "Please select a container from the list first.")
    
    def on_cancel():
        choice_window.destroy()
    
    def on_double_click(event):
        on_select()
    
    listbox.bind('<Double-Button-1>', on_double_click)
    
    def show_context_menu(event):
        selection = listbox.curselection()
        if selection:
            context_menu = tk.Menu(choice_window, tearoff=0)
            context_menu.add_command(label="Delete Container", 
                                  command=lambda: delete_container(selection[0]))
            context_menu.tk_popup(event.x_root, event.y_root)
    
    def delete_container(index):
        container_to_delete = listbox.containers[index]
        container_name = os.path.basename(container_to_delete)
        
        confirm = messagebox.askyesno(
            "Delete Container", 
            f"Are you sure you want to delete this container?\n\n{container_name}\n\n"
            "This will move it to Trash. Continue?"
        )
        
        if confirm:
            try:
                subprocess.run(['mv', container_to_delete, os.path.expanduser("~/.Trash/")], check=True)
                
                listbox.delete(index)
                listbox.containers.pop(index)
                
                messagebox.showinfo("Success", f"Container '{container_name}' moved to Trash.")
                
            except Exception as e:
                messagebox.showerror("Error", f"Failed to delete container: {str(e)}")
    
    listbox.bind('<Button-3>', show_context_menu)
    
    tk.Button(button_frame, text="Cancel", command=on_cancel, width=15).pack(side=tk.LEFT, padx=10)
    tk.Button(button_frame, text="Select", command=on_select, width=15).pack(side=tk.LEFT, padx=10)
    
    choice_window.wait_window()
    
    if result[0]:
        container_path = result[0]
        fortnite_game_path = os.path.join(container_path, "Data/Documents/FortniteGame")
        if os.path.exists(fortnite_game_path):
            return fortnite_game_path
        else:
            return container_path
    
    return None

def open_fortnite_game_directory():
    fortnite_path = get_fortnite_container_path()
    
    if fortnite_path is None:
        return
    
    try:
        subprocess.run(['open', '-R', fortnite_path], check=True)
    except subprocess.CalledProcessError as e:
        messagebox.showerror("Error", f"Failed to open directory in Finder: {str(e)}")
    except Exception as e:
        messagebox.showerror("Error", f"Unexpected error: {str(e)}")

def show_container_info():
    container_path = get_fortnite_container_path()
    
    if container_path:
        message = (
            f"Fortnite Game Directory Found:\n\n"
            f"Path: {container_path}\n\n"
            "This directory contains Fortnite's game data, settings, and cache files.\n"
            "You can access it in Finder by pressing Cmd+Shift+G and pasting the path."
        )
        messagebox.showinfo("Container Directory", message)
    else:
        messagebox.showerror("Error", "Could not find Fortnite's container. Make sure to open Fortnite at least once before proceeding.")

REFRESH_ICON_BASE64 = """
R0lGODlhEAAQAMQAAO/v7+zs7OLg4N/f3+Li4uDg4N3d3ejo6OHh4d7e3ubm5t3d3eHh4d/f39/f
3+Dg4OHh4ejo6N3d3d7e3uLi4t3d3eDg4OHh4ejo6N3d3eHh4QAA
ACH5BAEAABwALAAAAAAQABAAAAVRYCSOZGl+ZQpCZJrvqTQiVq7vdYJgsDofD8SYJCKfT0fEQPD9
fYCFEQzQeB5oOgoRUKjdbrfcrnY7nZ7P63O4XGy3u2y1u8PhcLi7XC6Hw+Hw+n0BFiYBLCMhIQA7
"""

def check_for_updates():
    try:
        headers = {"Accept": "application/vnd.github.v3+json"}
        response = requests.get(GITHUB_RELEASES_URL, headers=headers, timeout=10)
        response.raise_for_status()
        latest_release = response.json()
        latest_version = latest_release["tag_name"].lstrip('v') 
        
        current_parts = [int(x) for x in VERSION.split('.')]
        latest_parts = [int(x) for x in latest_version.split('.')]
        
        if latest_parts > current_parts:
            show_update_dialog(latest_version)
    except Exception as e:
        print(f"Failed to check for updates: {str(e)}")

def show_update_dialog(latest_version):
    update_window = tk.Toplevel(root)
    update_window.title("Update Available")
    update_window.geometry("400x200")
    update_window.grab_set()
    
    message = (
        f"A new version ({latest_version}) is available!\n"
        f"Current version: {VERSION}\n\n"
        "Please update to the latest version as the currently\n"
        "installed version could stop working."
    )
    tk.Label(update_window, text=message, justify="center").pack(pady=20)
    
    button_frame = tk.Frame(update_window)
    button_frame.pack(pady=20)
    
    tk.Button(button_frame, text="Update Now", 
              command=lambda: [webbrowser.open("https://github.com/isacucho/FnMacAssistant/releases/latest"), 
                             update_window.destroy()]).pack(side=tk.LEFT, padx=10)
    tk.Button(button_frame, text="Ignore", 
              command=update_window.destroy).pack(side=tk.LEFT, padx=10)

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
    progress_label.pack(pady=5)  
    progress_bar.pack(pady=5)   
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

def show_update_skip_info():
    messagebox.showinfo("Update Skip Feature", 
                      "Enable this when updating the game. To facilitate the update process, "
                      "this will automatically open Fortnite and let it crash before proceeding with the patch.")

def open_fortnite_and_wait():
    try:
        if os.path.exists(FORTNITE_APP_PATH):
            status_label.config(text="Opening Fortnite.app...")
            root.update()
            
            subprocess.Popen(['open', FORTNITE_APP_PATH])
            
            status_label.config(text="Waiting for app to crash...")
            root.update()
            
            for i in range(5):
                time.sleep(1)
                status_label.config(text=f"Waiting for app to crash... ({5-i}s)")
                root.update()
                
            status_label.config(text="Ready to patch")
            return True
        else:
            messagebox.showerror("Error", "Fortnite.app not found")
            status_label.config(text="")
            return False
    except Exception as e:
        messagebox.showerror("Error", f"Failed to open Fortnite.app: {str(e)}")
        status_label.config(text="")
        return False

def patch_app():
    provision_url = "https://github.com/isacucho/FnMacAssistant/raw/main/files/embedded.mobileprovision"
    temp_path = "/tmp/embedded.mobileprovision"
    provision_dest_path = os.path.join(FORTNITE_APP_PATH, "Wrapper/FortniteClient-IOS-Shipping.app/embedded.mobileprovision")

    try:
        if update_skip_var.get():
            if not open_fortnite_and_wait():
                return

        response = requests.get(provision_url, stream=True)
        response.raise_for_status()
        with open(temp_path, 'wb') as provision_file:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    provision_file.write(chunk)

        if not os.path.exists(os.path.dirname(provision_dest_path)):
            os.makedirs(os.path.dirname(provision_dest_path))
        shutil.move(temp_path, provision_dest_path)

        messagebox.showinfo("Patch Complete", "Fortnite has been patched. You can now open it.")
        status_label.config(text="")
    except Exception as e:
        if isinstance(e, (PermissionError, OSError)) and "Operation not permitted" in str(e):
            permission_message = (
                "Failed to patch the app due to missing permissions.\n\n"
                "Please grant 'Full Disk Access' or 'App Management' permissions to FnMacAssistant:\n\n"
                "1. Open System Settings > Privacy & Security.\n"
                "2. Find and click on 'Full Disk Access'.\n"
                "3. Add FnMacAssistant and make sure it's enabled.\n"
                "4. If patching still fails, try enabling it under 'App Management' as well.\n\n"
                "After granting permissions, please restart the application."
            )
            messagebox.showerror("Permissions Required", permission_message)
        else:
            messagebox.showerror("Error", f"Failed to patch the app: {str(e)}")
        status_label.config(text="")

def import_archive():
    """Import a zip file or PersistentDownloadDir folder into the FortniteGame folder"""
    from tkinter import filedialog
    
    fortnite_path = get_fortnite_container_path()
    
    if fortnite_path is None:
        return
    
    import_window = tk.Toplevel(root)
    import_window.title("Select Archive Type")
    import_window.geometry("280x150")
    import_window.grab_set()
    import_window.resizable(False, False)
    
    import_window.transient(root)
    import_window.grab_set()
    
    content_frame = tk.Frame(import_window)
    content_frame.pack(expand=True, fill='both', padx=15, pady=15)
    
    title_label = tk.Label(content_frame, text="Select your archive type", 
                          font=("Arial", 11, "bold"))
    title_label.pack(pady=(0, 15))
    
    button_frame = tk.Frame(content_frame)
    button_frame.pack(pady=15)

    button_frame.grid_columnconfigure(0, weight=1)
    button_frame.grid_columnconfigure(1, weight=1)
    
    def on_zip_select():
        import_window.destroy()
        selected_path = filedialog.askopenfilename(
            title="Select ZIP Archive File",
            filetypes=[("ZIP files", "*.zip"), ("All files", "*.*")]
        )
        
        if not selected_path:
            return
            
        if os.path.basename(fortnite_path) == "FortniteGame":
            target_dir = fortnite_path
        else:
            target_dir = os.path.join(fortnite_path, "Data/Documents/FortniteGame")
        
        if not os.path.exists(target_dir):
            messagebox.showerror("Error", f"Target directory not found: {target_dir}")
            return
            
        import_thread = threading.Thread(target=import_zip_file, args=(selected_path, target_dir))
        import_thread.start()
    
    def on_folder_select():
        import_window.destroy()
        selected_path = filedialog.askdirectory(
            title="Select PersistentDownloadDir Folder"
        )
        
        if not selected_path:
            return
            
        folder_name = os.path.basename(selected_path)
        if folder_name != "PersistentDownloadDir":
            messagebox.showerror("Error", "Selected folder must be named 'PersistentDownloadDir' to import.")
            return
            
        if os.path.basename(fortnite_path) == "FortniteGame":
            target_dir = fortnite_path
        else:
            target_dir = os.path.join(fortnite_path, "Data/Documents/FortniteGame")
        
        if not os.path.exists(target_dir):
            messagebox.showerror("Error", f"Target directory not found: {target_dir}")
            return
            
        import_thread = threading.Thread(target=import_persistant_folder, args=(selected_path, target_dir))
        import_thread.start()
    
    zip_button = tk.Button(button_frame, text="ZIP File", command=on_zip_select, 
                          height=2)
    zip_button.grid(row=0, column=0, sticky="ew", padx=(0, 5))
    
    folder_button = tk.Button(button_frame, text="Folder", command=on_folder_select, 
                            height=2)
    folder_button.grid(row=0, column=1, sticky="ew", padx=(5, 0))
    
    zip_button.focus_set()

def import_zip_file(zip_file_path, target_dir):
    try:
        zip_ref = zipfile.ZipFile(zip_file_path, 'r')
        
        try:
            file_list = zip_ref.namelist()
            
            confirm = messagebox.askyesno(
                "Import ZIP Archive",
                f"Import {len(file_list)} files from '{os.path.basename(zip_file_path)}' into FortniteGame folder?\n\n"
                "This will replace any existing files with the same names."
            )
            
            if not confirm:
                zip_ref.close()
                return
            
            print("Setting up progress bar for ZIP import...")
            progress_label.config(text="Starting ZIP import...")
            progress_label.pack(pady=5)
            progress_bar.pack(pady=5)
            progress_var.set(0)
            print("Progress bar should now be visible")
            
            for i, file_name in enumerate(file_list):
                try:
                    zip_ref.extract(file_name, target_dir)
                    
                    progress_percentage = ((i + 1) / len(file_list)) * 100
                    progress_var.set(progress_percentage)
                    progress_label.config(text=f"Imported {i + 1}/{len(file_list)} files")
                    print(f"Progress: {progress_percentage:.1f}% - {i + 1}/{len(file_list)} files")
                    
                    time.sleep(0.01)
                    
                except Exception as e:
                    print(f"Failed to extract {file_name}: {str(e)}")
                    continue
            
            progress_label.pack_forget()
            progress_bar.pack_forget()
            
            try:
                subprocess.run(['mv', zip_file_path, os.path.expanduser("~/.Trash/")], check=True)
            except subprocess.CalledProcessError:
                try:
                    os.remove(zip_file_path)
                except Exception as e:
                    print(f"Warning: Could not remove source file: {str(e)}")
            
            messagebox.showinfo("Success", f"Successfully imported {len(file_list)} files from ZIP archive.\n\n"
                              f"Archive moved to Trash.")
        
        finally:
            zip_ref.close()
            
    except zipfile.BadZipFile:
        messagebox.showerror("Error", "The selected file is not a valid ZIP archive.")
    except Exception as e:
        messagebox.showerror("Error", f"Failed to import ZIP archive: {str(e)}")
        progress_label.pack_forget()
        progress_bar.pack_forget()

def import_persistant_folder(source_folder, target_dir):
    try:
        total_files = 0
        for root, dirs, files in os.walk(source_folder):
            total_files += len(files)
        
        if total_files == 0:
            messagebox.showwarning("Warning", "The selected folder is empty.")
            return
        
        confirm = messagebox.askyesno(
            "Import PersistentDownloadDir",
            f"Import {total_files} files from '{os.path.basename(source_folder)}' into FortniteGame folder?\n\n"
            "This will merge the folder contents with existing PersistentDownloadDir."
        )
        
        if not confirm:
            return
        
        print("Setting up progress bar for folder import...")
        progress_label.config(text="Starting folder import...")
        progress_label.pack(pady=5)
        progress_bar.pack(pady=5)
        progress_var.set(0)
        print("Progress bar should now be visible")
        
        target_persistent_dir = os.path.join(target_dir, "PersistentDownloadDir")
        
        if os.path.exists(target_persistent_dir):
            print(f"Target directory exists, merging contents...")
            imported_files = 0
            
            for folder_root, dirs, files in os.walk(source_folder):
                rel_path = os.path.relpath(folder_root, source_folder)
                target_path = os.path.join(target_persistent_dir, rel_path)
                
                if not os.path.exists(target_path):
                    os.makedirs(target_path)
                
                for file in files:
                    try:
                        source_file = os.path.join(folder_root, file)
                        target_file = os.path.join(target_path, file)
                        
                        shutil.copy2(source_file, target_file)
                        
                        imported_files += 1
                        
                        progress_percentage = (imported_files / total_files) * 100
                        progress_var.set(progress_percentage)
                        progress_label.config(text=f"Imported {imported_files}/{total_files} files")
                        print(f"Progress: {progress_percentage:.1f}% - {imported_files}/{total_files} files")
                        
                        time.sleep(0.01)
                        
                    except Exception as e:
                        print(f"Failed to copy {file}: {str(e)}")
                        continue
            
            shutil.rmtree(source_folder)
            
        else:
            print(f"Target directory doesn't exist, moving entire folder...")
            shutil.move(source_folder, target_persistent_dir)
            imported_files = total_files
            
            progress_var.set(100)
            progress_label.config(text=f"Imported {imported_files}/{total_files} files")
        
        progress_label.pack_forget()
        progress_bar.pack_forget()
        
        
        messagebox.showinfo("Success", f"Successfully imported {imported_files} files from PersistentDownloadDir folder.\n\n"
                          f"Folder merged with existing PersistentDownloadDir in FortniteGame.")
        
    except Exception as e:
        messagebox.showerror("Error", f"Failed to import folder: {str(e)}")
        progress_label.pack_forget()
        progress_bar.pack_forget()

def show_delete_confirmation():
    if messagebox.askyesno("Delete Fortnite", 
                          "Are you sure you want to delete Fortnite?\nThis action cannot be reversed.", 
                          icon='warning',
                          default='no'):
        delete_fortnite_data()

def delete_fortnite_data():
    try:
        if os.path.exists(FORTNITE_APP_PATH):
            subprocess.run(['rm', '-rf', FORTNITE_APP_PATH], check=True)
            print("Fortnite.app deleted")
        
        fortnite_path = get_fortnite_container_path()
        if fortnite_path:
            if os.path.basename(fortnite_path) == "FortniteGame":
                container_path = os.path.dirname(os.path.dirname(fortnite_path))
            else:
                container_path = fortnite_path
            
            subprocess.run(['rm', '-rf', container_path], check=True)
            print("Fortnite container deleted")
        
        messagebox.showinfo("Success", "Fortnite app and data have been deleted.")
        
    except Exception as e:
        messagebox.showerror("Error", f"Failed to delete Fortnite: {str(e)}")

def show_archive_info():
    try:
        archive_gist_id = "6c1ad65c3ac11282fed669614a12c4a5"
        archive_gist_api_url = f"https://api.github.com/gists/{archive_gist_id}"
        
        headers = {"Accept": "application/vnd.github.v3+json"}
        response = requests.get(archive_gist_api_url, headers=headers, timeout=10)
        response.raise_for_status()
        
        gist_data = response.json()
        archive_file = gist_data["files"].get("archive.json")
        
        if not archive_file:
            messagebox.showerror("Error", "Archive file not found in gist.")
            return
            
        raw_url = archive_file["raw_url"]
        response = requests.get(raw_url, timeout=10)
        response.raise_for_status()
        
        archive_data = response.json()
        
        if not archive_data:
            messagebox.showwarning("No Archive Info", "No archive information available.")
            return
        
        latest_archive = archive_data[0]
        version = latest_archive.get("archive version", "Unknown")
        link = latest_archive.get("link", "")
        
        message = f"Latest Archive Available\n\nVersion: {version}\n\nThis archive contains the latest game files.\nDo you want to open the download page?"
        if messagebox.askyesno("Get Latest Archive", message, icon="info"):
            if link:
                webbrowser.open(link)
            else:
                messagebox.showerror("Error", "Download link not available.")
        
    except requests.RequestException as e:
        messagebox.showerror("Error", f"Failed to fetch archive information: {str(e)}")
    except ValueError as e:
        messagebox.showerror("Error", f"Invalid archive data format: {str(e)}")
    except Exception as e:
        messagebox.showerror("Error", f"Unexpected error: {str(e)}")


def show_ipa_info():
    messageIPA = f"For details on the differences between the IPAs, you can visit the project page.\n\nDo you want to open it in your browser?"
    if messagebox.askyesno("IPAs info", messageIPA, icon="info"):
         webbrowser.open("https://github.com/isacucho/FnMacAssistant#what-is-the-difference-between-the-various-ipas")


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
root.tk.call('tk', 'scaling', 2.0)
root.lift()
root.focus_force()
root.title("FnMacAssistant")
root.geometry("500x400") 

check_for_updates()

top_frame = tk.Frame(root)
top_frame.pack(pady=5)

ipa_combobox_label = tk.Label(top_frame, text="Select file to download:")
ipa_combobox_label.pack(pady=5)

dropdown_frame = tk.Frame(top_frame)
dropdown_frame.pack()

ipa_info_button = tk.Button(dropdown_frame, text="ⓘ", command=show_ipa_info, width=1, height=1)
ipa_info_button.pack(side=tk.LEFT, padx=(0, 5))

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

patch_frame = tk.Frame(root)
patch_frame.pack(pady=10)

patch_button = tk.Button(patch_frame, text="Patch App", command=patch_app, width=40, height=2)
patch_button.pack(pady=5)

import_frame = tk.Frame(patch_frame)
import_frame.pack(pady=5)

folder_frame = tk.Frame(import_frame, width=38, height=38)
folder_frame.pack_propagate(False) 

folder_button = tk.Button(
    folder_frame,
    text="📁",
    command=open_fortnite_game_directory,
    font=("Arial", 14),  
    relief=tk.FLAT,
    bg="#f0f0f0",
    bd=0,
    highlightthickness=0
)
folder_button.pack(expand=True, fill="both")  

folder_frame.pack(side=tk.LEFT, padx=(0, 5))


import_archive_button = tk.Button(import_frame, text="Import Archive", command=import_archive, width=35, height=2)
import_archive_button.pack(side=tk.LEFT, padx=(0, 5))


button_frame = tk.Frame(import_frame, width=38, height=38)
button_frame.pack_propagate(False)  

archive_info_button = tk.Button(
    button_frame,
    text="🔗",
    command=show_archive_info,
    font=("Arial", 14),
    relief=tk.FLAT,
    bg="#f0f0f0",
    bd=0,
    highlightthickness=0
)
archive_info_button.pack(expand=True, fill="both")

button_frame.pack(side=tk.LEFT, padx=5)

delete_fortnite_button = tk.Button(patch_frame, text="Delete Fortnite App and Data", 
                                  command=lambda: show_delete_confirmation(), width=40, height=2)
delete_fortnite_button.pack(pady=5)

progress_frame = tk.Frame(root)
progress_frame.pack(pady=5)

progress_var = tk.DoubleVar()
progress_bar = ttk.Progressbar(progress_frame, variable=progress_var, maximum=100, length=400)
progress_label = tk.Label(progress_frame, text="")

update_skip_frame = tk.Frame(root)
update_skip_frame.pack(pady=5)

update_skip_var = tk.BooleanVar()
update_skip_toggle = ttk.Checkbutton(update_skip_frame, text="Update Skip", variable=update_skip_var)
update_skip_toggle.pack(side=tk.LEFT, padx=5)

info_button = tk.Button(update_skip_frame, text="ⓘ", command=show_update_skip_info, 
                      width=2, font=("Arial", 10), relief=tk.FLAT)
info_button.pack(side=tk.LEFT)

status_label = tk.Label(root, text="", font=("Arial", 10))
status_label.pack(pady=5)

root.mainloop()
