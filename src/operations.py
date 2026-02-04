import os
import requests
import shutil
import zipfile
import time
from .config import PROVISION_URL
from .app_container import AppContainerManager


class DownloadCancelled(Exception):
    pass


def resolve_fortnite_app_path(status_callback=None):
    applications_dir = "/Applications"

    candidates = {
        "Fortnite.app": os.path.join(applications_dir, "Fortnite.app"),
        "Fortnite-1.app": os.path.join(applications_dir, "Fortnite-1.app"),
        "FortniteClient-IOS-Shipping.app": os.path.join(
            applications_dir, "FortniteClient-IOS-Shipping.app"
        ),
    }

    existing = {
        name: path for name, path in candidates.items()
        if os.path.exists(path)
    }

    if not existing:
        raise Exception("Fortnite is not installed. Please install it first.")

    if "Fortnite.app" in existing and len(existing) > 1:
        if status_callback:
            status_callback("Resolving multiple Fortnite installations...")

        if os.path.isdir(existing["Fortnite.app"]):
            shutil.rmtree(existing["Fortnite.app"])
        else:
            os.remove(existing["Fortnite.app"])

        preferred = (
            existing.get("Fortnite-1.app")
            or existing.get("FortniteClient-IOS-Shipping.app")
        )

        os.rename(preferred, candidates["Fortnite.app"])

    elif "Fortnite.app" not in existing:
        if status_callback:
            status_callback("Normalizing Fortnite app installation...")

        preferred = (
            existing.get("Fortnite-1.app")
            or existing.get("FortniteClient-IOS-Shipping.app")
        )

        os.rename(preferred, candidates["Fortnite.app"])

    return candidates["Fortnite.app"]


def download_ipa_task(
        url,
        name,
        size,
        progress_callback=None,
        completion_callback=None,
        error_callback=None,
        cancel_event=None):
    download_path = os.path.expanduser(f"~/Downloads/{name}")
    try:
        response = requests.get(url, stream=True)
        response.raise_for_status()
        downloaded_size = 0
        chunk_size = 8192
        with open(download_path, 'wb') as ipa_file:
            for chunk in response.iter_content(chunk_size=chunk_size):
                if cancel_event is not None and cancel_event.is_set():
                    raise DownloadCancelled("Download cancelled")
                if chunk:
                    ipa_file.write(chunk)
                    downloaded_size += len(chunk)
                    if progress_callback:
                        progress_callback(downloaded_size, size)

        if completion_callback:
            completion_callback()

    except Exception as e:
        if isinstance(e, DownloadCancelled):
            try:
                if os.path.exists(download_path):
                    os.remove(download_path)
            except Exception:
                pass
        if error_callback:
            error_callback(e)


def patch_app_task(
        status_callback=None,
        completion_callback=None,
        error_callback=None):

    temp_path = "/tmp/embedded.mobileprovision"

    try:
        resolved_app_path = resolve_fortnite_app_path(status_callback)

        from . import config
        config.FORTNITE_APP_PATH = resolved_app_path

        provision_dest_path = os.path.join(
            resolved_app_path,
            "Wrapper/FortniteClient-IOS-Shipping.app/embedded.mobileprovision"
        )

        app_manager = AppContainerManager()

        if status_callback:
            status_callback("Opening Fortnite.app...")

        if app_manager.open_app():
            if status_callback:
                status_callback("Waiting for app to verify...")

                for i in range(5):
                    time.sleep(1)
                    if status_callback:
                        status_callback(
                            f"Waiting for app to verify... ({5 - i}s)")
            else:
                raise Exception("Fortnite.app not found")

        if status_callback:
            status_callback("Downloading provision profile...")

        response = requests.get(PROVISION_URL, stream=True)
        response.raise_for_status()

        with open(temp_path, 'wb') as provision_file:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    provision_file.write(chunk)

        os.makedirs(os.path.dirname(provision_dest_path), exist_ok=True)
        shutil.move(temp_path, provision_dest_path)

        if completion_callback:
            completion_callback()

    except Exception as e:
        if error_callback:
            error_callback(e)


def import_zip_task(
        zip_file_path,
        target_dir,
        progress_callback=None,
        completion_callback=None,
        error_callback=None):
    try:
        zip_ref = zipfile.ZipFile(zip_file_path, 'r')
        try:
            file_list = zip_ref.namelist()
            total_files = len(file_list)

            for i, file_name in enumerate(file_list):
                zip_ref.extract(file_name, target_dir)
                if progress_callback:
                    progress_callback(i + 1, total_files)
                # Small delay to let UI update if needed, though callbacks
                # should handle it
                time.sleep(0.001)

            if completion_callback:
                completion_callback(total_files)

        finally:
            zip_ref.close()

    except Exception as e:
        if error_callback:
            error_callback(str(e))


def import_folder_task(
        source_folder,
        target_dir,
        progress_callback=None,
        completion_callback=None,
        error_callback=None):
    try:
        total_files = 0
        for root, _, files in os.walk(source_folder):
            total_files += len(files)

        target_persistent_dir = os.path.join(
            target_dir, "PersistentDownloadDir")

        if os.path.exists(target_persistent_dir):
            imported_files = 0
            for folder_root, _, files in os.walk(source_folder):
                rel_path = os.path.relpath(folder_root, source_folder)
                target_path = os.path.join(target_persistent_dir, rel_path)

                if not os.path.exists(target_path):
                    os.makedirs(target_path)

                for file in files:
                    source_file = os.path.join(folder_root, file)
                    target_file = os.path.join(target_path, file)
                    shutil.copy2(source_file, target_file)
                    imported_files += 1
                    if progress_callback:
                        progress_callback(imported_files, total_files)

            shutil.rmtree(source_folder)
            if completion_callback:
                completion_callback(imported_files)

        else:
            shutil.move(source_folder, target_persistent_dir)
            if progress_callback:
                progress_callback(total_files, total_files)
            if completion_callback:
                completion_callback(total_files)

    except Exception as e:
        if error_callback:
            error_callback(str(e))
