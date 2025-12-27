import os
import plistlib
import subprocess
from .config import FORTNITE_APP_PATH
from .utils import has_full_disk_access, prompt_for_full_disk_access

class AppContainerManager:
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
