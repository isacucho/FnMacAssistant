import tkinter as tk
from tkinter import messagebox, ttk, filedialog
import tkinter.font as tkfont
import threading
import webbrowser
import os
import subprocess

from .config import VERSION
from .utils import load_refresh_icon
from .api import APIClient
from .app_container import AppContainerManager
from .operations import download_ipa_task, patch_app_task, import_zip_task, import_folder_task, DownloadCancelled
from .gui_container_selector import ContainerSelectorWindow


# --- UI Constants ---
GAP_S = 8
GAP_M = 10
GAP_L = 16
GAP_XL = 20
GAP_XXL = 24

PAD_WINDOW = (GAP_XXL, GAP_S)
PAD_SECTION_INNER = (14, 12)
PAD_SECTION_TITLE = (GAP_XL, 0)
FONT_SCALE_TITLE = 1.0

class FnMacAssistantApp:
    def __init__(self, root):
        self.root = root
        self.root.title("FnMacAssistant")
        self.root.minsize(640, 0)
        self.root.resizable(True, True)
        self.root.tk.call('tk', 'scaling', 2.0)
        
        self.api_client = APIClient()
        self.app_manager = AppContainerManager()
        self.ipa_files_dict = {}
        
        # Container info
        self.containers = []
        self.current_container = None
        
        self.setup_ui()
        self.check_updates()

    def _apply_ttk_style(self):
        style = ttk.Style(self.root)
        for theme in ("aqua", "clam", "alt", "default"):
            try:
                style.theme_use(theme)
                break
            except tk.TclError:
                continue

        default_font = tkfont.nametofont("TkDefaultFont")
        self.title_font = default_font.copy()
        self.title_font.configure(size=int(default_font.cget("size") * FONT_SCALE_TITLE))

        style.configure("TButton", padding=(10, 6))
        style.configure("TCheckbutton", padding=(4, 2))
        style.configure("TCombobox", padding=(4, 2))
        style.configure("Red.TButton", foreground="darkred")
        style.configure("Info.TButton", padding=(0, 0))
        return style

    def _create_section(self, parent, title_text, info_command=None, refresh_command=None):
        # Custom title frame with label and optional button
        title_frame = ttk.Frame(parent)
        title_frame.pack(fill="x", pady=PAD_SECTION_TITLE)

        title_label = ttk.Label(title_frame, text=title_text, font=self.title_font, anchor="w")
        title_label.pack(side="left")

        if info_command:
            info_label = ttk.Label(title_frame, text="ⓘ", cursor="hand2")
            info_label.pack(side="right")
            info_label.bind("<Button-1>", lambda e: info_command())

        if refresh_command:
            refresh_label = ttk.Label(title_frame, text="↻", cursor="hand2", font=(None, 14))
            refresh_label.pack(side="right", padx=(0, GAP_S))
            refresh_label.bind("<Button-1>", lambda e: refresh_command())

        # Bordered content frame using Labelframe with empty text
        content_frame = ttk.Labelframe(parent, text="", padding=PAD_SECTION_INNER)
        content_frame.pack(fill="x", pady=(0, GAP_L))
        return content_frame

    def _show_progress(self, show: bool, message: str = ""):
        if show:
            self.progress_label.config(text=message)
            self.progress_bar.pack(fill="x")
            self.progress_label.pack(fill="x", pady=(GAP_S, 0))
        else:
            self.progress_bar.pack_forget()

    def _set_download_state(self, downloading: bool):
        if downloading:
            self.download_button.state(["disabled"])
            self.cancel_download_button.pack(side="right")
        else:
            self.download_button.state(["!disabled"])
            self.cancel_download_button.pack_forget()
        
    def setup_ui(self):
        self._apply_ttk_style()

        # Main container
        main_frame = ttk.Frame(self.root, padding=PAD_WINDOW)
        main_frame.pack(fill="both", expand=True)

        # --- Section 1: Download ---
        ipa_frame = self._create_section(main_frame, "⬇️ Download", info_command=self.show_ipa_info)

        # Row 1: Label | Combobox | Refresh
        ipa_row1 = ttk.Frame(ipa_frame)
        ipa_row1.pack(fill="x", pady=(0, GAP_M))

        ttk.Label(ipa_row1, text="IPA file").pack(side="left")

        refresh_icon = load_refresh_icon()
        if refresh_icon:
            self.refresh_icon = refresh_icon
            refresh_btn = ttk.Button(ipa_row1, image=self.refresh_icon, command=self.refresh_dropdown)
        else:
            refresh_btn = ttk.Button(ipa_row1, text="↻", command=self.refresh_dropdown)
        refresh_btn.pack(side="right", padx=(GAP_S, 0))

        self.ipa_combobox = ttk.Combobox(ipa_row1, state="readonly")
        self.ipa_combobox.pack(side="left", fill="x", expand=True, padx=(GAP_S, 0))

        # Row 2: Download | Patch
        download_row = ttk.Frame(ipa_frame)
        download_row.pack(fill="x")

        self.download_button = ttk.Button(download_row, text="Download Selected IPA", command=self.start_download)
        self.download_button.pack(side="left", fill="x", expand=True, padx=(0, GAP_S))

        ttk.Button(download_row, text="Patch App", command=self.patch_app).pack(side="left", fill="x", expand=True)

        # --- Section 2: Game Data ---
        data_frame = self._create_section(main_frame, "📦 Game Data", refresh_command=self.detect_current_path)

        # Row 1: Label | Entry | Change | Open
        data_row1 = ttk.Frame(data_frame)
        data_row1.pack(fill="x", pady=(0, GAP_M))

        ttk.Label(data_row1, text="Current Path:").pack(side="left")
        
        ttk.Button(data_row1, text="Open", command=self.open_fortnite_directory).pack(side="right")
        
        self.change_data_folder_button = ttk.Button(data_row1, text="Change", command=self.change_data_folder)
        self.change_data_folder_button.pack(side="right", padx=(GAP_S, 0))

        self.path_var = tk.StringVar(value="Detecting...")
        self.path_entry = ttk.Entry(data_row1, textvariable=self.path_var, state="disabled")
        self.path_entry.pack(side="left", fill="x", expand=True, padx=(GAP_S, 0))

        # Additional path info
        self.path_info_frame = ttk.Frame(data_frame)
        self.path_info_frame.pack(fill="x", pady=(0, GAP_M))

        archive_row = ttk.Frame(data_frame)
        archive_row.pack(fill="x", pady=(GAP_M, 0))

        ttk.Label(archive_row, text="Archives:").pack(side="left")
        ttk.Button(archive_row, text="Import Archive", command=self.import_archive).pack(side="left", padx=(GAP_S, 0))
        ttk.Button(archive_row, text="🔗", command=self.show_archive_info).pack(side="left")
        ttk.Button(archive_row, text="Delete App & Data", command=self.confirm_delete, style="Red.TButton").pack(side="right")

        # --- Status / Settings (unbordered) ---
        # Update Skip
        update_skip_row = ttk.Frame(main_frame)
        update_skip_row.pack(fill="x", pady=(GAP_XL, GAP_S))
        
        self.update_skip_var = tk.BooleanVar()
        ttk.Checkbutton(update_skip_row, text="Enable Update Skip", variable=self.update_skip_var).pack(side="left")
        
        info_label = ttk.Label(update_skip_row, text="ⓘ", cursor="hand2")
        info_label.pack(side="right")
        info_label.bind("<Button-1>", lambda e: self.show_update_skip_info())

        # Separator
        ttk.Separator(main_frame, orient="horizontal").pack(fill="x", pady=(0, 8))

        # Progress Container
        self.progress_frame = ttk.Frame(main_frame)
        self.progress_frame.pack(fill="x")

        self.progress_var = tk.DoubleVar()
        self.progress_bar = ttk.Progressbar(self.progress_frame, variable=self.progress_var, maximum=100)
        # Packed in _show_progress

        self.progress_label = ttk.Label(self.progress_frame, text="")
        # Packed in _show_progress

        # Status Row
        status_row = ttk.Frame(main_frame)
        status_row.pack(fill="x", pady=(GAP_M, 0))

        self.cancel_download_button = ttk.Button(status_row, text="✖️", command=self.cancel_download)
        # Packed in _set_download_state

        self._show_progress(False)

        self.download_cancel_event = None
        self._set_download_state(False)

        self.populate_ipa_dropdown()
        self.detect_current_path()

    def detect_current_path(self):
        self.containers = self.app_manager.get_containers()
        if not self.containers:
            self.path_var.set("Not found")
            self.current_container = None
            if hasattr(self, "change_data_folder_button"):
                self.change_data_folder_button.state(["disabled"])
            return

        # Try to find the best container (one that has FortniteGame folder)
        best_container = self.containers[0]
        for c in self.containers:
             # Check if Data/Documents/FortniteGame exists
             if os.path.exists(os.path.join(c, "Data/Documents/FortniteGame")):
                  best_container = c
                  break
        
        # If we already have a current container and it's still valid, keep it
        if self.current_container and self.current_container in self.containers:
            pass # Keep current
        else:
            self.current_container = best_container

        data_dir = self.app_manager.get_container_data_path(self.current_container)
        if not os.path.exists(data_dir):
            self.path_var.set("Not found")
            if hasattr(self, "change_data_folder_button"):
                self.change_data_folder_button.state(["disabled"])
            return

        # If Data is a symlink, show its target path
        display_path = self.app_manager.get_container_data_display_path(self.current_container)
        self.path_var.set(display_path)
        if hasattr(self, "change_data_folder_button"):
            self.change_data_folder_button.state(["!disabled"])

    def get_container_root(self):
        containers = self.app_manager.get_containers()
        if not containers:
            messagebox.showerror("Error", "Could not find Fortnite's container.")
            return None
        if len(containers) == 1 and not self.app_manager.DEV_FORCE_MULTIPLE_CONTAINERS:
            return containers[0]
        return self.ask_user_to_choose_container_root(containers)

    def ask_user_to_choose_container_root(self, containers):
        selector = ContainerSelectorWindow(self.root, containers, self.app_manager)
        return selector.show()

    def change_data_folder(self):
        # Do not allow switching if we can't locate the current Game Data folder
        container_root = self.get_container_root()
        if not container_root:
            messagebox.showerror("Error", "Fortnite game data folder not found.")
            return

        current_data_dir = self.app_manager.get_container_data_path(container_root)
        if not os.path.exists(current_data_dir):
            messagebox.showerror("Error", "Fortnite game data folder not found.")
            return

        folder_selected = filedialog.askdirectory(title="Select New Game Data Folder")
        if not folder_selected:
            return

        if not messagebox.askyesno(
            "Confirm",
            "This will switch Fortnite's container Game Data folder to the selected folder using a symlink.\n\nContinue?",
            icon="warning",
        ):
            return

        self.update_status("Switching game data folder...")
        self.progress_var.set(0)
        self._show_progress(True, "Switching game data folder...")

        def worker():
            try:
                result = self.app_manager.switch_data_folder(container_root, folder_selected)
                self.root.after(0, lambda: self._on_switch_data_folder_success(result))
            except Exception as e:
                self.root.after(0, lambda err=e: self._on_switch_data_folder_error(err))

        threading.Thread(target=worker, daemon=True).start()

    def _on_switch_data_folder_success(self, result: dict):
        self._show_progress(False)
        self.update_status("Ready")
        self.detect_current_path()

        status = result.get("status", "ok")
        if status == "already":
            messagebox.showinfo("Game Data Folder", "Selected folder is already in use.")
            return

        if status == "backed_up_and_linked":
            backup = result.get("backup", "")
            messagebox.showinfo(
                "Game Data Folder Updated",
                "Game data folder switched successfully.\n\n"
                f"A backup of the old Game Data folder was created at:\n{backup}",
            )
            return

        messagebox.showinfo("Game Data Folder Updated", "Game data folder switched successfully.")

    def _on_switch_data_folder_error(self, error: Exception):
        self._show_progress(False)
        self.update_status("Ready")
        if isinstance(error, (PermissionError, OSError)) and "Operation not permitted" in str(error):
            messagebox.showerror("Permissions Required", "Operation failed due to missing permissions. Please grant Full Disk Access.")
            return
        messagebox.showerror("Error", str(error))

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
        ttk.Label(update_window, text=message, justify="center").pack(pady=GAP_XL)
        
        button_frame = ttk.Frame(update_window)
        button_frame.pack(pady=GAP_XL)
        
        ttk.Button(button_frame, text="Update Now", 
                  command=lambda: [webbrowser.open("https://github.com/isacucho/FnMacAssistant/releases/latest"), 
                                 update_window.destroy()]).pack(side=tk.LEFT, padx=10)
        ttk.Button(button_frame, text="Ignore", 
                  command=update_window.destroy).pack(side=tk.LEFT, padx=10)

    def populate_ipa_dropdown(self, force=False):
        self.ipa_files_dict = {}
        # Run in thread to avoid freezing UI
        threading.Thread(target=self._fetch_ipa_data, args=(force,)).start()

    def _fetch_ipa_data(self, force=False):
        ipa_files = self.api_client.get_ipa_data(force)
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
        self.populate_ipa_dropdown(force=True)
        messagebox.showinfo("Refresh", "File list refreshed.")

    def show_ipa_info(self):
        if messagebox.askyesno("IPAs info", "For details on the differences between the IPAs, you can visit the project page.\n\nDo you want to open it in your browser?", icon="info"):
             webbrowser.open("https://github.com/isacucho/FnMacAssistant#what-is-the-difference-between-the-various-ipas")

    def show_archive_info(self):
        info = self.api_client.get_archive_info()
        if info:
            version = info.get("archive version", "Unknown")
            link = info.get("link", "")
            message = f"Latest Game Data Archive Available\n\nVersion: {version}\n\nThis archive contains the latest game data files.\nDo you want to open the download page?"
            if messagebox.askyesno("Get Latest Game Data Archive", message, icon="info"):
                if link:
                    webbrowser.open(link)
                else:
                    messagebox.showerror("Error", "Download link not available.")
        else:
            messagebox.showwarning("No Game Data Archive Info", "No game data archive information available.")

    def show_update_skip_info(self):
        messagebox.showinfo("Update Skip Feature", 
                          "Enable this when updating the game. To facilitate the update process, "
                          "this will automatically open Fortnite and let it crash before proceeding with the patch.")

    def start_download(self):
        selected_ipa = self.ipa_combobox.get()
        if selected_ipa and selected_ipa in self.ipa_files_dict:
            data = self.ipa_files_dict[selected_ipa]

            self.progress_var.set(0)
            self._show_progress(True, "Starting download...")
            self.download_cancel_event = threading.Event()
            self._set_download_state(True)
            
            threading.Thread(target=download_ipa_task, 
                           args=(data['browser_download_url'], data['name'], data['size']),
                           kwargs={
                               'progress_callback': self.update_download_progress,
                               'completion_callback': self.download_complete,
                               'error_callback': self.operation_error,
                               'cancel_event': self.download_cancel_event,
                           }).start()
        else:
            messagebox.showerror("Error", "Please select a valid file.")

    def cancel_download(self):
        if self.download_cancel_event is not None:
            self.download_cancel_event.set()
            self.update_status("Cancelling download...")
            self._show_progress(True, "Cancelling download...")

    def update_download_progress(self, downloaded, total):
        if total > 0:
            percentage = (downloaded / total) * 100
            self.progress_var.set(percentage)
            self.progress_label.config(text=f"Downloaded {downloaded/(1024*1024):.2f} MB of {total/(1024*1024):.2f} MB")
        else:
            self.progress_label.config(text=f"Downloaded {downloaded/(1024*1024):.2f} MB")

    def download_complete(self):
        messagebox.showinfo("Download Complete", "Download completed!\n\nProceed with the app installation, open the game and make sure it crashes, then return here and patch.")
        self._show_progress(False)
        self._set_download_state(False)
        self.download_cancel_event = None

    def patch_app(self):
        threading.Thread(target=patch_app_task,
                       args=(self.update_skip_var.get(),),
                       kwargs={
                           'status_callback': self.update_status,
                           'completion_callback': self.patch_complete,
                           'error_callback': self.patch_error
                       }).start()

    def update_status(self, text):
        self.progress_label.config(text=text)
        self.progress_label.pack(fill="x", pady=(GAP_M, 0))

    def patch_complete(self):
        self.progress_label.config(text="")
        messagebox.showinfo("Patch Complete", "Fortnite has been patched. You can now open it.")

    def patch_error(self, error):
        self.progress_label.config(text="")
        if isinstance(error, (PermissionError, OSError)) and "Operation not permitted" in str(error):
            messagebox.showerror("Permissions Required", "Failed to patch due to missing permissions. Please grant Full Disk Access.")
        else:
            messagebox.showerror("Error", f"Failed to patch: {str(error)}")

    def operation_error(self, error):
        self._show_progress(False)
        self._set_download_state(False)
        self.download_cancel_event = None
        if isinstance(error, DownloadCancelled):
            self.update_status("Ready")
            messagebox.showinfo("Download", "Download cancelled.")
            return
        messagebox.showerror("Error", f"Operation failed: {str(error)}")

    def open_fortnite_directory(self):
        container = self.get_container_root()
        if container:
            path = self.app_manager.resolve_game_path(container)
            subprocess.run(['open', '-R', path])

    def confirm_delete(self):
        if messagebox.askyesno("Delete Fortnite", "Are you sure you want to delete Fortnite?\nThis action cannot be reversed.", icon='warning', default='no'):
            try:
                container = self.get_container_root()
                if container:
                    path = self.app_manager.resolve_game_path(container)
                    if self.app_manager.delete_data(path):
                        messagebox.showinfo("Success", "Fortnite app and data have been deleted.")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to delete: {str(e)}")

    def import_archive(self):
        container = self.get_container_root()
        if not container:
            return
            
        path = self.app_manager.resolve_game_path(container)

        import_window = tk.Toplevel(self.root)
        import_window.title("Select Game Data Archive Type")
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

        ttk.Button(import_window, text="ZIP File", command=on_zip).pack(pady=GAP_M)
        ttk.Button(import_window, text="Folder", command=on_folder).pack(pady=GAP_M)

    def start_import_zip(self, zip_path, target_dir):
        self.progress_var.set(0)
        self._show_progress(True, "Starting ZIP import...")
        
        threading.Thread(target=import_zip_task, args=(zip_path, target_dir),
                       kwargs={
                           'progress_callback': self.update_import_progress,
                           'completion_callback': self.import_complete,
                           'error_callback': self.operation_error
                       }).start()

    def start_import_folder(self, folder_path, target_dir):
        self.progress_var.set(0)
        self._show_progress(True, "Starting folder import...")
        
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
        self._show_progress(False)
        messagebox.showinfo("Success", f"Successfully imported {count} files.")
