import os
import plistlib
import subprocess
import shutil
import time
from .config import FORTNITE_APP_PATH, SYMLINK_TARGET_SUBPATH
from .utils import has_full_disk_access, prompt_for_full_disk_access

class AppContainerManager:
    # Set to True to force multiple containers detection for UI testing
    DEV_FORCE_MULTIPLE_CONTAINERS = True

    def get_container_data_path(self, container_root: str) -> str:
        return os.path.join(container_root, "Data", "Documents", "FortniteGame")

    def get_directory_size_display(self, path: str) -> str:
        try:
            # -h for human readable
            cmd = ['du', '-sh', path]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                # Output is like "12G    /path/to/dir"
                return result.stdout.split()[0]
        except Exception:
            pass
        return "Unknown"

    def get_container_data_display_path(self, container_root: str) -> str:
        # Determine the path that might be a symlink based on configuration
        symlink_source = os.path.join(container_root, SYMLINK_TARGET_SUBPATH) if SYMLINK_TARGET_SUBPATH else container_root
        
        if os.path.islink(symlink_source):
             try:
                link_target = os.readlink(symlink_source)
                if not os.path.isabs(link_target):
                    link_target = os.path.abspath(os.path.join(os.path.dirname(symlink_source), link_target))
                
                # We need to return the path to the Game Data (Data/Documents/FortniteGame)
                # We know the full relative path from container root is "Data/Documents/FortniteGame"
                full_rel_path = "Data/Documents/FortniteGame"
                
                # Calculate what part of the path is "remaining" after the symlink
                if SYMLINK_TARGET_SUBPATH == "":
                    remaining = full_rel_path
                elif full_rel_path.startswith(SYMLINK_TARGET_SUBPATH):
                    # Remove prefix. +1 for separator if not empty match
                    if len(SYMLINK_TARGET_SUBPATH) < len(full_rel_path):
                         remaining = full_rel_path[len(SYMLINK_TARGET_SUBPATH):].lstrip(os.sep)
                    else:
                         remaining = ""
                else:
                    # Fallback if config is weird
                    return os.path.realpath(self.get_container_data_path(container_root))

                return os.path.join(link_target, remaining)
             except OSError:
                 pass

        return self.get_container_data_path(container_root)

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
        if os.path.basename(path) not in ["Data", "FortniteGame"]:
            return False
        container_root = os.path.dirname(os.path.dirname(path)) if os.path.basename(path) == "FortniteGame" else os.path.dirname(path)
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

        # Determine what we are moving/linking based on config
        source_path = os.path.join(container_root, SYMLINK_TARGET_SUBPATH) if SYMLINK_TARGET_SUBPATH else container_root
        
        if not os.path.exists(source_path):
             raise FileNotFoundError(f"Source path not found: {source_path}")

        source_name = os.path.basename(source_path)
        target_path = os.path.join(target_data_root, source_name)
        
        current_real = os.path.realpath(source_path)
        target_real = os.path.realpath(target_path)

        if current_real == target_real:
            return {"status": "already", "current": source_path, "target": target_path}

        # Prevent choosing something inside the container itself
        if os.path.commonpath([current_real, os.path.realpath(target_data_root)]) == current_real:
            raise ValueError("Target folder cannot be inside the source directory")

        # If current is already a symlink, just repoint it.
        if os.path.islink(source_path):
            # If we are just moving the storage location:
            old_target = os.readlink(source_path)
            if os.path.exists(old_target) and not os.path.exists(target_path):
                shutil.move(old_target, target_path)
            
            os.unlink(source_path)
            os.symlink(target_path, source_path)
            return {"status": "relinked", "current": source_path, "target": target_path}

        # Standard case: Move physical folder to target and link back
        if not os.path.exists(target_path):
            shutil.move(source_path, target_path)
            os.symlink(target_path, source_path)
            return {"status": "moved_and_linked", "current": source_path, "target": target_path}
        
        # Target exists: remove current content and link
        if os.path.isdir(source_path):
            shutil.rmtree(source_path)
        else:
            os.remove(source_path)
            
        os.symlink(target_path, source_path)
        return {"status": "replaced_and_linked", "current": source_path, "target": target_path}

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
            
            # Merge both lists and remove duplicates
            all_containers = list(set(fortnite_containers + fallback_containers))
            
            if self.DEV_FORCE_MULTIPLE_CONTAINERS and len(all_containers) > 0:
                 # Duplicate the first one for testing UI
                 all_containers.append(all_containers[0])

            if not all_containers:
                return []
                
            return all_containers
                
        except Exception as e:
            print(f"Error getting Fortnite container path: {str(e)}")
            return []

    def resolve_game_path(self, container_path):
        """Given a container path, returns the FortniteGame path or the container path itself."""
        fortnite_game_path = os.path.join(container_path, "Data/Documents/FortniteGame")
        if os.path.islink(fortnite_game_path):
             target = os.readlink(fortnite_game_path)
             if not os.path.isabs(target):
                 target = os.path.abspath(os.path.join(os.path.dirname(fortnite_game_path), target))
             return target
        if os.path.exists(fortnite_game_path):
            return fortnite_game_path
        else:
            return container_path

    def open_app(self):
        if os.path.exists(FORTNITE_APP_PATH):
            subprocess.Popen(['open', FORTNITE_APP_PATH])
            return True
        return False

    def delete_container(self, container_path):
        """Deletes only the specified container, leaving the app installed."""
        try:
            if container_path:
                # Handle if we were passed the internal FortniteGame path
                if os.path.basename(container_path) == "FortniteGame":
                    # .../Data/Documents/FortniteGame -> .../Data/Documents -> .../Data -> ContainerRoot
                    # Actually resolve_game_path returns .../Data/Documents/FortniteGame
                    # But the container path in the list is usually the root container path.
                    # Let's be safe.
                    # If path ends with FortniteGame, go up 3 levels? 
                    # No, let's assume we get the container root from the list.
                    # But just in case:
                    if "Data/Documents/FortniteGame" in container_path:
                         real_container_to_delete = container_path.split("/Data/Documents/FortniteGame")[0]
                    else:
                         real_container_to_delete = container_path
                else:
                    real_container_to_delete = container_path
                
                if os.path.exists(real_container_to_delete):
                    subprocess.run(['rm', '-rf', real_container_to_delete], check=True)
                    print(f"Container deleted: {real_container_to_delete}")
                    return True
        except Exception as e:
            raise e
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
