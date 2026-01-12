import os
import plistlib
import subprocess
import shutil
from .config import FORTNITE_APP_PATH, SYMLINK_TARGET_SUBPATH
from .utils import has_full_disk_access, prompt_for_full_disk_access


class AppContainerManager:
    # Set to True to force multiple containers detection for UI testing
    DEV_FORCE_MULTIPLE_CONTAINERS = True

    def get_container_data_path(self, container_root: str) -> str:
        """Returns the standard MacOS container data path, ignoring symlinks."""
        return os.path.join(
            container_root,
            "Data",
            "Documents",
            "FortniteGame")

    def is_using_symlink(self, container_root: str) -> bool:
        if not container_root:
            return False
        symlink_source = os.path.join(
            container_root,
            SYMLINK_TARGET_SUBPATH) if SYMLINK_TARGET_SUBPATH else container_root
        return os.path.islink(symlink_source)

    def get_directory_size_display(self, path: str) -> str:
        try:
            cmd = ['du', '-sh', path]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                return result.stdout.split()[0]
        except Exception:
            pass
        return "Unknown"

    def get_container_data_display_path(self, container_root: str) -> str:
        symlink_source = os.path.join(
            container_root,
            SYMLINK_TARGET_SUBPATH) if SYMLINK_TARGET_SUBPATH else container_root

        if os.path.islink(symlink_source):
            try:
                link_target = os.readlink(symlink_source)
                if not os.path.isabs(link_target):
                    link_target = os.path.abspath(os.path.join(
                        os.path.dirname(symlink_source), link_target))

                full_rel_path = "Data/Documents/FortniteGame"

                if SYMLINK_TARGET_SUBPATH == "":
                    remaining = full_rel_path
                elif full_rel_path.startswith(SYMLINK_TARGET_SUBPATH):
                    if len(SYMLINK_TARGET_SUBPATH) < len(full_rel_path):
                        remaining = full_rel_path[len(
                            SYMLINK_TARGET_SUBPATH):].lstrip(os.sep)
                    else:
                        remaining = ""
                else:
                    return os.path.realpath(
                        self.get_container_data_path(container_root))

                return os.path.join(link_target, remaining)
            except OSError:
                pass

        return self.get_container_data_path(container_root)

    def switch_data_folder(
            self,
            container_root: str,
            target_data_root: str) -> dict:
        if not container_root or not os.path.isdir(container_root):
            raise FileNotFoundError("Container root not found")

        if not target_data_root or not os.path.isdir(target_data_root):
            raise FileNotFoundError("Target folder not found")

        # Validation: Target folder must be empty OR contain only
        # 'FortniteGame'
        items = os.listdir(target_data_root)
        if items:
            if len(items) == 1 and items[0] == "FortniteGame":
                pass
            else:
                raise ValueError(
                    "Selected folder must be empty or contain only 'FortniteGame' folder.")

        if not has_full_disk_access():
            prompt_for_full_disk_access()
            raise PermissionError("Full Disk Access is required")

        source_path = os.path.join(
            container_root,
            SYMLINK_TARGET_SUBPATH) if SYMLINK_TARGET_SUBPATH else container_root

        source_name = os.path.basename(source_path)

        target_path = os.path.join(target_data_root, source_name)

        current_real = os.path.realpath(source_path)
        target_real = os.path.realpath(target_path)

        if current_real == target_real:
            return {
                "status": "already",
                "current": source_path,
                "target": target_path}

        if os.path.commonpath([current_real, os.path.realpath(
                target_data_root)]) == current_real:
            raise ValueError(
                "Target folder cannot be inside the source directory")

        target_exists_and_valid = (os.path.exists(
            target_path) and os.path.isdir(target_path))

        if os.path.islink(source_path):
            old_real_content = os.readlink(source_path)
            if not os.path.isabs(old_real_content):
                old_real_content = os.path.abspath(os.path.join(
                    os.path.dirname(source_path), old_real_content))

            if not target_exists_and_valid and os.path.exists(
                    old_real_content):
                shutil.move(old_real_content, target_path)

            os.unlink(source_path)
            os.symlink(target_path, source_path)
            return {
                "status": "relinked",
                "current": source_path,
                "target": target_path}

        if not target_exists_and_valid:
            if os.path.exists(source_path):
                shutil.move(source_path, target_path)
            else:
                os.makedirs(target_path, exist_ok=True)
        else:
            if os.path.exists(source_path):
                shutil.rmtree(source_path)

        os.symlink(target_path, source_path)
        return {
            "status": "moved_and_linked",
            "current": source_path,
            "target": target_path}

    def reset_data_location(self, container_root: str) -> bool:
        if not container_root or not self.is_using_symlink(container_root):
            return False

        if not has_full_disk_access():
            prompt_for_full_disk_access()
            raise PermissionError("Full Disk Access is required")

        symlink_source = os.path.join(
            container_root,
            SYMLINK_TARGET_SUBPATH) if SYMLINK_TARGET_SUBPATH else container_root

        if os.path.islink(symlink_source):
            try:
                link_target_path = os.readlink(symlink_source)
                if not os.path.isabs(link_target_path):
                    link_target_path = os.path.abspath(os.path.join(
                        os.path.dirname(symlink_source), link_target_path))

                os.unlink(symlink_source)

                if os.path.exists(link_target_path):
                    shutil.move(link_target_path, symlink_source)
                    print(
                        f"Reset symlink: Moved {link_target_path} back to {symlink_source}")
                else:
                    os.makedirs(symlink_source, exist_ok=True)
                    print(
                        f"Reset symlink: Target missing, recreated empty folder at {symlink_source}")

                return True
            except Exception as e:
                print(f"Error resetting symlink: {e}")
                raise e
        return False

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
                metadata_path = os.path.join(
                    container_path, ".com.apple.containermanagerd.metadata.plist")

                if os.path.exists(metadata_path):
                    try:
                        with open(metadata_path, 'rb') as f:
                            metadata = plistlib.load(f)
                            bundle_id = metadata.get(
                                'MCMMetadataIdentifier', '').lower()
                            if bundle_id and 'fortnite' in bundle_id:
                                print(
                                    f"Found Fortnite container through bundle ID: {container_path}")
                                fortnite_containers.append(container_path)
                            else:
                                metadata_str = str(metadata).lower()
                                if 'fortnite' in metadata_str:
                                    print(
                                        f"Found Fortnite container through metadata search: {container_path}")
                                    fortnite_containers.append(container_path)
                    except Exception as e:
                        print(
                            f"Error reading metadata for {container_path}: {
                                str(e)}")
                        continue

                fortnite_game_path = os.path.join(
                    container_path, "Data/Documents/FortniteGame")
                if os.path.exists(fortnite_game_path) or os.path.islink(
                        fortnite_game_path):
                    print(
                        f"Found FortniteGame directory in container: {container_path}")
                    fallback_containers.append(container_path)

            # Merge both lists and remove duplicates
            all_containers = list(
                set(fortnite_containers + fallback_containers))

            if self.DEV_FORCE_MULTIPLE_CONTAINERS and len(all_containers) > 0:
                # Duplicate the first one for testing UI
                all_containers.append(all_containers[0])

            if not all_containers:
                return []

            return all_containers

        except Exception as e:
            print(f"Error getting Fortnite container path: {str(e)}")
            return []

    def get_fortnite_downloaded_data_path(
            self, container_root_path: str) -> str:
        """
        Returns the absolute path to the FortniteGame directory.
        The OS handles symlink resolution if the data folder is redirected.
        """
        return os.path.join(
            container_root_path,
            "Data",
            "Documents",
            "FortniteGame")

    def open_app(self):
        if os.path.exists(FORTNITE_APP_PATH):
            subprocess.Popen(['open', FORTNITE_APP_PATH])
            return True
        return False

    def delete_container(self, container_path):
        """Deletes only the specified container, leaving the app installed."""
        try:
            if not container_path:
                return False

            # Validate if it is a proper container root by checking metadata
            metadata_path = os.path.join(
                container_path, ".com.apple.containermanagerd.metadata.plist")
            if not os.path.exists(metadata_path):
                print(
                    f"Invalid container path (missing metadata): {container_path}")
                return False

            # Sanity Check
            if container_path == "/" or container_path.strip() == "":
                return False

            if os.path.exists(container_path):
                subprocess.run(['rm', '-rf', container_path], check=True)
                print(f"Container deleted: {container_path}")
                return True
        except Exception as e:
            raise e

    def delete_app_and_data(self, container_path=None):
        try:
            if os.path.exists(FORTNITE_APP_PATH):
                subprocess.run(['rm', '-rf', FORTNITE_APP_PATH], check=True)
                print("Fortnite.app deleted")

            if container_path:
                if self.delete_container(container_path):
                    print("Fortnite container deleted")
                    return True
                else:
                    print("Failed to delete container or invalid path")
                    # Return True if app was deleted even if container failed?
                    # Previous logic returned True if container path was provided and deleted.
                    # If container_path provided but failed, it might be confusing.
                    # Use existing behavior: if container_path is provided,
                    # success depends on it.
                    return False
            return True
        except Exception as e:
            raise e
