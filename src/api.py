import requests
import time
import json
import os
from .config import GITHUB_RELEASES_URL, GIST_API_URL, ARCHIVE_GIST_API_URL, VERSION


class APIClient:
    CACHE_FILE = os.path.expanduser("~/.fnmac_cache.json")
    CACHE_EXPIRY = 600  # 10 minutes

    def __init__(self):
        self.session = requests.Session()
        self.cache = self._load_cache()

    def _load_cache(self):
        if os.path.exists(self.CACHE_FILE):
            try:
                with open(self.CACHE_FILE, 'r') as f:
                    return json.load(f)
            except BaseException:
                pass
        return {}

    def _save_cache(self):
        try:
            with open(self.CACHE_FILE, 'w') as f:
                json.dump(self.cache, f)
        except BaseException:
            pass

    def _get_cached(self, key):
        if key in self.cache:
            data = self.cache[key]
            if time.time() - data.get('timestamp', 0) < self.CACHE_EXPIRY:
                return data['data'], True
        return None, False

    def _get_cached_expired(self, key):
        if key in self.cache:
            data = self.cache[key]
            return data['data']
        return None

    def _set_cached(self, key, data):
        self.cache[key] = {'data': data, 'timestamp': time.time()}
        self._save_cache()

    def check_for_updates(self, force=False):
        """Checks for updates and returns the latest version if an update is available, else None."""
        if not force:
            cached, is_cached = self._get_cached('updates')
            if is_cached:
                return cached

        try:
            headers = {"Accept": "application/vnd.github.v3+json"}
            response = self.session.get(
                GITHUB_RELEASES_URL, headers=headers, timeout=10)
            response.raise_for_status()
            latest_release = response.json()
            latest_version = latest_release["tag_name"].lstrip('v')

            current_parts = [int(x) for x in VERSION.split('.')]
            latest_parts = [int(x) for x in latest_version.split('.')]

            result = latest_version if latest_parts > current_parts else None
            self._set_cached('updates', result)
            return result
        except Exception as e:
            print(f"Failed to check for updates: {str(e)}")
            # Fallback to expired cache
            cached = self._get_cached_expired('updates')
            if cached is not None:
                print("Using expired cache for updates")
                return cached
            return None

    def get_latest_raw_url(self, force=False):
        if not force:
            cached, is_cached = self._get_cached('raw_url')
            if is_cached:
                return cached

        try:
            headers = {"Accept": "application/vnd.github.v3+json"}
            response = self.session.get(
                GIST_API_URL, headers=headers, timeout=10)
            response.raise_for_status()
            gist_data = response.json()
            raw_url = gist_data["files"]["list.json"]["raw_url"]
            print("Latest raw URL:", raw_url)
            self._set_cached('raw_url', raw_url)
            return raw_url
        except Exception as e:
            print(f"Failed to fetch Gist metadata: {str(e)}")
            # Fallback to expired cache
            cached = self._get_cached_expired('raw_url')
            if cached is not None:
                print("Using expired cache for raw_url")
                return cached
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

    def get_ipa_data(self, force=False):
        if not force:
            cached, is_cached = self._get_cached('ipa_data')
            if is_cached:
                return cached

        try:
            raw_url = self.get_latest_raw_url(force)
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
            self._set_cached('ipa_data', ipa_files)
            return ipa_files
        except Exception as e:
            print(f"Error getting IPA data: {e}")
            # Fallback to expired cache
            cached = self._get_cached_expired('ipa_data')
            if cached is not None:
                print("Using expired cache for ipa_data")
                return cached
            return []

    def get_archive_info(self, force=False):
        if not force:
            cached, is_cached = self._get_cached('archive_info')
            if is_cached:
                return cached

        try:
            headers = {"Accept": "application/vnd.github.v3+json"}
            response = self.session.get(
                ARCHIVE_GIST_API_URL, headers=headers, timeout=10)
            response.raise_for_status()

            gist_data = response.json()
            archive_file = gist_data["files"].get("archive.json")

            if not archive_file:
                result = None
            else:
                raw_url = archive_file["raw_url"]
                response = self.session.get(raw_url, timeout=10)
                response.raise_for_status()

                archive_data = response.json()

                result = archive_data[0] if archive_data else None

            self._set_cached('archive_info', result)
            return result

        except Exception as e:
            print(f"Failed to fetch archive information: {str(e)}")
            # Fallback to expired cache
            cached = self._get_cached_expired('archive_info')
            if cached is not None:
                print("Using expired cache for archive_info")
                return cached
            return None
