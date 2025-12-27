import os
import plistlib
import subprocess
import shutil
import time
from .config import FORTNITE_APP_PATH
from .utils import has_full_disk_access, prompt_for_full_disk_access

class AppContainerManager:
    def get_container_data_path(self, container_root: str) -> str:
        return os.path.join(container_root, "Data")

    def get_container_data_display_path(self, container_root: str) -> str:
        data_dir = self.get_container_data_path(container_root)
        if os.path.islink(data_dir):
            try:
                link_target = os.readlink(data_dir)
                if not os.path.isabs(link_target):
                    link_target = os.path.abspath(os.path.join(os.path.dirname(data_dir), link_target))
                return link_target
            except OSError:
                return os.path.realpath(data_dir)
        return data_dir

    def is_empty_dir(self, path: str) -> bool:
        try:
            return os.path.isdir(path) and not os.listdir(path)
        except Exception:
            return False

    def is_fortnite_data_root(self, data_root: str) -> bool:
        if not os.path.isdir(data_root):
            return False
        candidates = [
            os.path.join(data_root, "Documents", "FortniteGame"),
            os.path.join(data_root, "Documents", "FortniteGame", "Saved"),
            os.path.join(data_root, "Documents", "FortniteGame", "PersistentDownloadDir"),
        ]
        return any(os.path.exists(p) for p in candidates)

    def is_container_data_folder(self, path: str) -> bool:
        if not os.path.isdir(path):
            return False
        if os.path.basename(path) != "Data":
            return False
        container_root = os.path.dirname(path)
        metadata_path = os.path.join(container_root, ".com.apple.containermanagerd.metadata.plist")
        return os.path.exists(metadata_path)

    def switch_data_folder(self, container_root: str, target_data_root: str) -> dict:
        if not container_root or not os.path.isdir(container_root):
            raise FileNotFoundError("Container root not found")

        if not target_data_root or not os.path.isdir(target_data_root):
            raise FileNotFoundError("Target folder not found")

        if not has_full_disk_access():
            prompt_for_full_disk_access()
            raise PermissionError("Full Disk Access is required")

        current_data_dir = self.get_container_data_path(container_root)
        if not os.path.exists(current_data_dir):
            raise FileNotFoundError(f"Current data folder not found: {current_data_dir}")

        current_data_real = os.path.realpath(current_data_dir)
        target_real = os.path.realpath(target_data_root)

        if current_data_real == target_real:
            return {"status": "already", "current": current_data_dir, "target": target_data_root}

        # Prevent choosing something inside the container itself (can create recursion/odd states)
        container_real = os.path.realpath(container_root)
        if os.path.commonpath([container_real, target_real]) == container_real:
            raise ValueError("Target folder cannot be inside the container directory")

        target_is_empty = self.is_empty_dir(target_data_root)
        target_has_structure = self.is_fortnite_data_root(target_data_root) or self.is_container_data_folder(target_data_root)
        target_is_allowed = target_is_empty or target_has_structure
        if not target_is_allowed:
            raise ValueError(
                "Target folder must be empty or already contain Fortnite data structure (Documents/FortniteGame)"
            )

        # If current is already a symlink, just repoint it.
        if os.path.islink(current_data_dir):
            os.unlink(current_data_dir)
            os.symlink(target_data_root, current_data_dir)
            return {"status": "relinked", "current": current_data_dir, "target": target_data_root}

        if target_is_empty:
            # Move the contents over, then replace Data/ with a symlink
            for name in os.listdir(current_data_dir):
                src = os.path.join(current_data_dir, name)
                dst = os.path.join(target_data_root, name)
                shutil.move(src, dst)

            # Current Data should now be empty
            try:
                os.rmdir(current_data_dir)
            except OSError as e:
                raise OSError(f"Could not remove original Data folder (not empty?): {e}")

            os.symlink(target_data_root, current_data_dir)
            return {"status": "moved_and_linked", "current": current_data_dir, "target": target_data_root}

        # Target has structure: do not merge/overwrite; backup current and link
        timestamp = time.strftime("%Y%m%d-%H%M%S")
        backup_path = f"{current_data_dir}.backup-{timestamp}"
        shutil.move(current_data_dir, backup_path)
        os.symlink(target_data_root, current_data_dir)
        return {
            "status": "backed_up_and_linked",
            "current": current_data_dir,
            "target": target_data_root,
            "backup": backup_path,
        }

    def get_containers(self):
        """
        Returns a list of potential Fortnite container paths.
        If only one is found, returns a list with one element.
        If none, returns empty list.
        """
        try:
            containers_dir = os.path.expanduser("~/Library/Containers")
            if not os.path.exists(containers_dir):
                return []
            
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
            
            return fortnite_containers
                
        except Exception as e:
            print(f"Error getting Fortnite container path: {str(e)}")
            return []

    def resolve_game_path(self, container_path):
        """Given a container path, returns the FortniteGame path or the container path itself."""
        fortnite_game_path = os.path.join(container_path, "Data/Documents/FortniteGame")
        if os.path.exists(fortnite_game_path):
            return fortnite_game_path
        else:
            return container_path

    def open_app(self):
        if os.path.exists(FORTNITE_APP_PATH):
            subprocess.Popen(['open', FORTNITE_APP_PATH])
            return True
        return False

    def delete_data(self, container_path=None):
        try:
            if os.path.exists(FORTNITE_APP_PATH):
                subprocess.run(['rm', '-rf', FORTNITE_APP_PATH], check=True)
                print("Fortnite.app deleted")
            
            if container_path:
                if os.path.basename(container_path) == "FortniteGame":
                    real_container_to_delete = os.path.dirname(os.path.dirname(container_path))
                else:
                    real_container_to_delete = container_path
                
                subprocess.run(['rm', '-rf', real_container_to_delete], check=True)
                print("Fortnite container deleted")
                return True
        except Exception as e:
            raise e
        return False
