import tkinter as tk
from tkinter import messagebox, ttk, filedialog
import threading
import webbrowser
import os
import subprocess

from .config import VERSION
from .utils import load_refresh_icon
from .api import APIClient
from .app_container import AppContainerManager
from .operations import download_ipa_task, patch_app_task, import_zip_task, import_folder_task

class FnMacAssistantApp:
    def __init__(self, root):
        self.root = root
        self.root.title("FnMacAssistant")
        self.root.geometry("500x400")
        self.root.tk.call('tk', 'scaling', 2.0)
        
        self.api_client = APIClient()
        self.app_manager = AppContainerManager()
        self.ipa_files_dict = {}
        
        self.setup_ui()
        self.check_updates()
        
    def setup_ui(self):
        # Top Frame - IPA Selection
        top_frame = tk.Frame(self.root)
        top_frame.pack(pady=5)

        tk.Label(top_frame, text="Select file to download:").pack(pady=5)

        dropdown_frame = tk.Frame(top_frame)
        dropdown_frame.pack()

        tk.Button(dropdown_frame, text="ⓘ", command=self.show_ipa_info, width=1, height=1).pack(side=tk.LEFT, padx=(0, 5))

        self.ipa_combobox = ttk.Combobox(dropdown_frame, width=40)
        self.ipa_combobox.pack(side=tk.LEFT, padx=(0, 10))

        refresh_icon = load_refresh_icon()
        if refresh_icon:
            self.refresh_icon = refresh_icon # Keep reference
            refresh_btn = tk.Button(dropdown_frame, image=self.refresh_icon, command=self.refresh_dropdown, 
                                  width=24, height=24, borderwidth=0, padx=0, pady=0)
        else:
            refresh_btn = tk.Button(dropdown_frame, text="↻", command=self.refresh_dropdown, width=1, height=1)
        refresh_btn.pack(side=tk.LEFT)

        # Download Button
        tk.Button(self.root, text="Download File", command=self.start_download, width=40, height=2).pack(pady=20)

        # Patch Frame
        patch_frame = tk.Frame(self.root)
        patch_frame.pack(pady=10)

        tk.Button(patch_frame, text="Patch App", command=self.patch_app, width=40, height=2).pack(pady=5)

        # Import Frame
        import_frame = tk.Frame(patch_frame)
        import_frame.pack(pady=5)

        folder_frame = tk.Frame(import_frame, width=38, height=38)
        folder_frame.pack_propagate(False)
        tk.Button(folder_frame, text="📁", command=self.open_fortnite_directory, font=("Arial", 14),
                 relief=tk.FLAT, bg="#f0f0f0", bd=0, highlightthickness=0).pack(expand=True, fill="both")
        folder_frame.pack(side=tk.LEFT, padx=(0, 5))

        tk.Button(import_frame, text="Import Archive", command=self.import_archive, width=35, height=2).pack(side=tk.LEFT, padx=(0, 5))

        archive_info_frame = tk.Frame(import_frame, width=38, height=38)
        archive_info_frame.pack_propagate(False)
        tk.Button(archive_info_frame, text="🔗", command=self.show_archive_info, font=("Arial", 14),
                 relief=tk.FLAT, bg="#f0f0f0", bd=0, highlightthickness=0).pack(expand=True, fill="both")
        archive_info_frame.pack(side=tk.LEFT, padx=5)

        # Delete Button
        tk.Button(patch_frame, text="Delete Fortnite App and Data", 
                 command=self.confirm_delete, width=40, height=2).pack(pady=5)

        # Progress
        progress_frame = tk.Frame(self.root)
        progress_frame.pack(pady=5)
        self.progress_var = tk.DoubleVar()
        self.progress_bar = ttk.Progressbar(progress_frame, variable=self.progress_var, maximum=100, length=400)
        self.progress_label = tk.Label(progress_frame, text="")

        # Update Skip
        update_skip_frame = tk.Frame(self.root)
        update_skip_frame.pack(pady=5)
        self.update_skip_var = tk.BooleanVar()
        ttk.Checkbutton(update_skip_frame, text="Update Skip", variable=self.update_skip_var).pack(side=tk.LEFT, padx=5)
        tk.Button(update_skip_frame, text="ⓘ", command=self.show_update_skip_info, 
                 width=2, font=("Arial", 10), relief=tk.FLAT).pack(side=tk.LEFT)

        # Status
        self.status_label = tk.Label(self.root, text="", font=("Arial", 10))
        self.status_label.pack(pady=5)

        # Initial Load
        self.populate_ipa_dropdown()

    def check_updates(self):
        latest_version = self.api_client.check_for_updates()
        if latest_version:
            self.show_update_dialog(latest_version)

    def show_update_dialog(self, latest_version):
        update_window = tk.Toplevel(self.root)
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

    def populate_ipa_dropdown(self):
        self.ipa_files_dict = {}
        # Run in thread to avoid freezing UI
        threading.Thread(target=self._fetch_ipa_data).start()

    def _fetch_ipa_data(self):
        ipa_files = self.api_client.get_ipa_data()
        if ipa_files:
            self.ipa_files_dict = {file['name']: file for file in ipa_files}
            self.root.after(0, self._update_dropdown, list(self.ipa_files_dict.keys()))
        else:
            self.root.after(0, self._update_dropdown, [])

    def _update_dropdown(self, values):
        self.ipa_combobox['values'] = values
        if values:
            self.ipa_combobox.current(0)
        else:
            self.ipa_combobox.set("No files available")

    def refresh_dropdown(self):
        self.populate_ipa_dropdown()
        messagebox.showinfo("Refresh", "File list refreshed.")

    def show_ipa_info(self):
        if messagebox.askyesno("IPAs info", "For details on the differences between the IPAs, you can visit the project page.\n\nDo you want to open it in your browser?", icon="info"):
             webbrowser.open("https://github.com/isacucho/FnMacAssistant#what-is-the-difference-between-the-various-ipas")

    def show_archive_info(self):
        info = self.api_client.get_archive_info()
        if info:
            version = info.get("archive version", "Unknown")
            link = info.get("link", "")
            message = f"Latest Archive Available\n\nVersion: {version}\n\nThis archive contains the latest game files.\nDo you want to open the download page?"
            if messagebox.askyesno("Get Latest Archive", message, icon="info"):
                if link:
                    webbrowser.open(link)
                else:
                    messagebox.showerror("Error", "Download link not available.")
        else:
            messagebox.showwarning("No Archive Info", "No archive information available.")

    def show_update_skip_info(self):
        messagebox.showinfo("Update Skip Feature", 
                          "Enable this when updating the game. To facilitate the update process, "
                          "this will automatically open Fortnite and let it crash before proceeding with the patch.")

    def start_download(self):
        selected_ipa = self.ipa_combobox.get()
        if selected_ipa and selected_ipa in self.ipa_files_dict:
            data = self.ipa_files_dict[selected_ipa]
            
            self.progress_label.pack(pady=5)
            self.progress_bar.pack(pady=5)
            self.progress_var.set(0)
            
            threading.Thread(target=download_ipa_task, 
                           args=(data['browser_download_url'], data['name'], data['size']),
                           kwargs={
                               'progress_callback': self.update_download_progress,
                               'completion_callback': self.download_complete,
                               'error_callback': self.operation_error
                           }).start()
        else:
            messagebox.showerror("Error", "Please select a valid file.")

    def update_download_progress(self, downloaded, total):
        if total > 0:
            percentage = (downloaded / total) * 100
            self.progress_var.set(percentage)
            self.progress_label.config(text=f"Downloaded {downloaded/(1024*1024):.2f} MB of {total/(1024*1024):.2f} MB")
        else:
            self.progress_label.config(text=f"Downloaded {downloaded/(1024*1024):.2f} MB")

    def download_complete(self):
        messagebox.showinfo("Download Complete", "Download completed!\n\nProceed with the app installation, open the game and make sure it crashes, then return here and patch.")
        self.progress_label.pack_forget()
        self.progress_bar.pack_forget()

    def patch_app(self):
        threading.Thread(target=patch_app_task,
                       args=(self.update_skip_var.get(),),
                       kwargs={
                           'status_callback': self.update_status,
                           'completion_callback': self.patch_complete,
                           'error_callback': self.patch_error
                       }).start()

    def update_status(self, text):
        self.status_label.config(text=text)

    def patch_complete(self):
        self.status_label.config(text="")
        messagebox.showinfo("Patch Complete", "Fortnite has been patched. You can now open it.")

    def patch_error(self, error):
        self.status_label.config(text="")
        if isinstance(error, (PermissionError, OSError)) and "Operation not permitted" in str(error):
            messagebox.showerror("Permissions Required", "Failed to patch due to missing permissions. Please grant Full Disk Access.")
        else:
            messagebox.showerror("Error", f"Failed to patch: {str(error)}")

    def operation_error(self, error):
        self.progress_label.pack_forget()
        self.progress_bar.pack_forget()
        messagebox.showerror("Error", f"Operation failed: {str(error)}")

    def get_container_path(self):
        containers = self.app_manager.get_containers()
        if not containers:
            messagebox.showerror("Error", "Could not find Fortnite's container.")
            return None
        
        if len(containers) == 1:
            return self.app_manager.resolve_game_path(containers[0])
        
        return self.ask_user_to_choose_container(containers)

    def ask_user_to_choose_container(self, containers):
        choice_window = tk.Toplevel(self.root)
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
        
        result = [None]
        
        def on_select():
            selection = listbox.curselection()
            if selection:
                result[0] = containers[selection[0]]
                choice_window.destroy()
        
        tk.Button(choice_window, text="Select", command=on_select).pack(pady=20)
        choice_window.wait_window()
        
        if result[0]:
            return self.app_manager.resolve_game_path(result[0])
        return None

    def open_fortnite_directory(self):
        path = self.get_container_path()
        if path:
            subprocess.run(['open', '-R', path])

    def confirm_delete(self):
        if messagebox.askyesno("Delete Fortnite", "Are you sure you want to delete Fortnite?\nThis action cannot be reversed.", icon='warning', default='no'):
            try:
                path = self.get_container_path()
                if self.app_manager.delete_data(path):
                    messagebox.showinfo("Success", "Fortnite app and data have been deleted.")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to delete: {str(e)}")

    def import_archive(self):
        path = self.get_container_path()
        if not path:
            return

        import_window = tk.Toplevel(self.root)
        import_window.title("Select Archive Type")
        import_window.geometry("280x150")
        
        def on_zip():
            import_window.destroy()
            file_path = filedialog.askopenfilename(filetypes=[("ZIP files", "*.zip"), ("All files", "*.*")])
            if file_path:
                self.start_import_zip(file_path, path)

        def on_folder():
            import_window.destroy()
            dir_path = filedialog.askdirectory()
            if dir_path:
                if os.path.basename(dir_path) != "PersistentDownloadDir":
                    messagebox.showerror("Error", "Selected folder must be named 'PersistentDownloadDir'")
                    return
                self.start_import_folder(dir_path, path)

        tk.Button(import_window, text="ZIP File", command=on_zip).pack(pady=10)
        tk.Button(import_window, text="Folder", command=on_folder).pack(pady=10)

    def start_import_zip(self, zip_path, target_dir):
        self.progress_label.pack(pady=5)
        self.progress_bar.pack(pady=5)
        self.progress_var.set(0)
        self.progress_label.config(text="Starting ZIP import...")
        
        threading.Thread(target=import_zip_task, args=(zip_path, target_dir),
                       kwargs={
                           'progress_callback': self.update_import_progress,
                           'completion_callback': self.import_complete,
                           'error_callback': self.operation_error
                       }).start()

    def start_import_folder(self, folder_path, target_dir):
        self.progress_label.pack(pady=5)
        self.progress_bar.pack(pady=5)
        self.progress_var.set(0)
        self.progress_label.config(text="Starting folder import...")
        
        threading.Thread(target=import_folder_task, args=(folder_path, target_dir),
                       kwargs={
                           'progress_callback': self.update_import_progress,
                           'completion_callback': self.import_complete,
                           'error_callback': self.operation_error
                       }).start()

    def update_import_progress(self, current, total):
        percentage = (current / total) * 100
        self.progress_var.set(percentage)
        self.progress_label.config(text=f"Imported {current}/{total} files")

    def import_complete(self, count):
        self.progress_label.pack_forget()
        self.progress_bar.pack_forget()
        messagebox.showinfo("Success", f"Successfully imported {count} files.")
