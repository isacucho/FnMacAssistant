import requests
from .config import GITHUB_RELEASES_URL, GIST_API_URL, ARCHIVE_GIST_API_URL, VERSION

class APIClient:
    def __init__(self):
        self.session = requests.Session()

    def check_for_updates(self):
        """Checks for updates and returns the latest version if an update is available, else None."""
        try:
            headers = {"Accept": "application/vnd.github.v3+json"}
            response = self.session.get(GITHUB_RELEASES_URL, headers=headers, timeout=10)
            response.raise_for_status()
            latest_release = response.json()
            latest_version = latest_release["tag_name"].lstrip('v') 
            
            current_parts = [int(x) for x in VERSION.split('.')]
            latest_parts = [int(x) for x in latest_version.split('.')]
            
            if latest_parts > current_parts:
                return latest_version
            return None
        except Exception as e:
            print(f"Failed to check for updates: {str(e)}")
            return None

    def get_latest_raw_url(self):
        try:
            headers = {"Accept": "application/vnd.github.v3+json"}
            response = self.session.get(GIST_API_URL, headers=headers, timeout=10)
            response.raise_for_status()
            gist_data = response.json()
            raw_url = gist_data["files"]["list.json"]["raw_url"]
            print("Latest raw URL:", raw_url)
            return raw_url
        except Exception as e:
            raise Exception(f"Failed to fetch Gist metadata: {str(e)}")

    def get_file_size(self, url):
        try:
            response = self.session.head(url, timeout=10, allow_redirects=True)
            if response.status_code == 200 and 'Content-Length' in response.headers:
                return int(response.headers['Content-Length'])
        except requests.RequestException:
            pass

        try:
            response = self.session.get(url, stream=True, timeout=10)
            response.raise_for_status()
            if 'Content-Length' in response.headers:
                return int(response.headers['Content-Length'])
            return None
        except requests.RequestException as e:
            print(f"Failed to fetch size for {url}: {str(e)}")
            return None

    def get_ipa_data(self):
        try:
            raw_url = self.get_latest_raw_url()
            if not raw_url:
                return []
            
            headers = {
                "Cache-Control": "no-cache, no-store, must-revalidate",
                "Pragma": "no-cache",
                "Expires": "0"
            }
            
            response = self.session.get(raw_url, headers=headers, timeout=10)
            response.raise_for_status()

            print("Fetching from:", raw_url)
            # print("Raw JSON:", response.text)

            ipa_data = response.json()
            ipa_files = []
            for item in ipa_data:
                if all(k in item for k in ['name', 'download_url']):
                    size = self.get_file_size(item['download_url'])
                    if size is None and 'size' in item:
                        size = item['size']
                    ipa_files.append({
                        'name': item['name'],
                        'browser_download_url': item['download_url'],
                        'size': size if size is not None else 0
                    })
            print("Parsed ipa_files:", ipa_files)
            return ipa_files
        except Exception as e:
            print(f"Error getting IPA data: {e}")
            return []

    def get_archive_info(self):
        try:
            headers = {"Accept": "application/vnd.github.v3+json"}
            response = self.session.get(ARCHIVE_GIST_API_URL, headers=headers, timeout=10)
            response.raise_for_status()
            
            gist_data = response.json()
            archive_file = gist_data["files"].get("archive.json")
            
            if not archive_file:
                return None
                
            raw_url = archive_file["raw_url"]
            response = self.session.get(raw_url, timeout=10)
            response.raise_for_status()
            
            archive_data = response.json()
            
            if not archive_data:
                return None
            
            return archive_data[0]
            
        except Exception as e:
            print(f"Failed to fetch archive information: {str(e)}")
            return None
