import tkinter as tk
from tkinter import ttk, messagebox
import tkinter.font as tkfont

GAP_S = 8
GAP_M = 10
GAP_L = 16
GAP_XL = 20

class ContainerSelectorWindow:
    def __init__(self, parent, containers, app_manager):
        self.parent = parent
        self.containers = containers
        self.app_manager = app_manager
        self.selected_container = None
        
        self.window = tk.Toplevel(parent)
        self.window.title("Select Fortnite Container")
        # Let the window size itself based on content, but set a reasonable minimum
        self.window.minsize(500, 300)
        
        # Make it modal
        self.window.transient(parent)
        self.window.grab_set()
        
        self._setup_ui()
        self._populate_list()
        
        # Center window on parent
        self._center_window()

    def _center_window(self):
        self.window.update_idletasks()
        width = self.window.winfo_width()
        height = self.window.winfo_height()
        x = (self.window.winfo_screenwidth() // 2) - (width // 2)
        y = (self.window.winfo_screenheight() // 2) - (height // 2)
        self.window.geometry(f'{width}x{height}+{x}+{y}')

    def _setup_ui(self):
        # Main layout container with padding
        main_frame = ttk.Frame(self.window, padding=GAP_L)
        main_frame.pack(fill="both", expand=True)

        # Header Section
        header_frame = ttk.Frame(main_frame)
        header_frame.pack(fill="x", pady=(0, GAP_L))

        title_font = tkfont.Font(family="Helvetica", size=16, weight="bold")
        ttk.Label(
            header_frame, 
            text="Multiple Fortnite Installations Found", 
            font=title_font
        ).pack(anchor="w")

        ttk.Label(
            header_frame,
            text="Please select the active installation below. The correct one usually has the largest size.",
            foreground="gray"
        ).pack(anchor="w", pady=(GAP_S, 0))

        # List Section (Treeview)
        list_frame = ttk.Frame(main_frame)
        list_frame.pack(fill="both", expand=True, pady=(0, GAP_L))

        # Scrollbar
        scrollbar = ttk.Scrollbar(list_frame)
        scrollbar.pack(side="right", fill="y")

        # Treeview
        columns = ("size", "path")
        self.tree = ttk.Treeview(
            list_frame, 
            columns=columns, 
            show="headings", 
            selectmode="browse",
            yscrollcommand=scrollbar.set
        )
        
        self.tree.heading("size", text="Size", anchor="w")
        self.tree.heading("path", text="Container Path", anchor="w")
        
        self.tree.column("size", width=80, minwidth=60, stretch=False)
        self.tree.column("path", width=450, minwidth=200, stretch=True)
        
        self.tree.pack(side="left", fill="both", expand=True)
        scrollbar.config(command=self.tree.yview)

        # Context Menu
        self.context_menu = tk.Menu(self.window, tearoff=0)
        self.context_menu.add_command(label="Delete Container", command=self.delete_selected_container)

        # Bindings
        self.tree.bind("<Double-1>", lambda e: self.confirm_selection())
        self.tree.bind("<<TreeviewSelect>>", self._on_select)
        
        # Right-click binding (Mac uses Button-2 or Control-Click usually, but Button-3 is standard right click)
        if self.window.tk.call('tk', 'windowingsystem') == 'aqua':
            self.tree.bind("<Button-2>", self._show_context_menu)
            self.tree.bind("<Button-3>", self._show_context_menu)
            self.tree.bind("<Control-1>", self._show_context_menu)
        else:
            self.tree.bind("<Button-3>", self._show_context_menu)

        # Footer / Action Section
        footer_frame = ttk.Frame(main_frame)
        footer_frame.pack(fill="x")

        self.info_label = ttk.Label(footer_frame, text="Select a container to continue", foreground="gray")
        self.info_label.pack(side="left", anchor="center")

        button_frame = ttk.Frame(footer_frame)
        button_frame.pack(side="right")

        ttk.Button(button_frame, text="Cancel", command=self.window.destroy).pack(side="left", padx=(0, GAP_S))
        self.select_button = ttk.Button(button_frame, text="Select Container", command=self.confirm_selection, state="disabled")
        self.select_button.pack(side="left")

    def _populate_list(self):
        # Use a set to track unique paths to avoid duplicates visually if any
        seen_paths = set()
        
        for container in self.containers:
            if container in seen_paths:
                continue
            seen_paths.add(container)
            
            # Calculate size (this might take a moment, could be threaded but for now it's ok)
            size_str = self.app_manager.get_directory_size_display(container)
            self.tree.insert("", "end", values=(size_str, container))

    def _on_select(self, event):
        selection = self.tree.selection()
        if selection:
            self.select_button.state(["!disabled"])
            self.info_label.config(text="Ready to select")
        else:
            self.select_button.state(["disabled"])
            self.info_label.config(text="Select a container to continue")

    def _show_context_menu(self, event):
        item = self.tree.identify_row(event.y)
        if item:
            self.tree.selection_set(item)
            self.context_menu.post(event.x_root, event.y_root)

    def delete_selected_container(self):
        selection = self.tree.selection()
        if not selection:
            return
            
        item = self.tree.item(selection[0])
        container_path = item['values'][1]
        
        if messagebox.askyesno(
            "Confirm Delete", 
            f"Are you sure you want to delete this container?\n\n{container_path}\n\nThis action cannot be undone.",
            parent=self.window,
            icon='warning'
        ):
            try:
                if self.app_manager.delete_container(container_path):
                    # Remove from internal list and UI
                    if container_path in self.containers:
                        self.containers.remove(container_path)
                    self.tree.delete(selection[0])
                    
                    messagebox.showinfo("Success", "Container deleted.", parent=self.window)
                    
                    if not self.containers:
                        self.window.destroy()
            except Exception as e:
                messagebox.showerror("Error", f"Failed to delete: {str(e)}", parent=self.window)

    def confirm_selection(self):
        selection = self.tree.selection()
        if selection:
            item = self.tree.item(selection[0])
            self.selected_container = item['values'][1]
            self.window.destroy()

    def show(self):
        self.window.wait_window()
        return self.selected_container
