VERSION = "1.5.0"
GITHUB_RELEASES_URL = "https://api.github.com/repos/isacucho/FnMacAssistant/releases/latest"
GIST_ID = "fb6a16acae4e592603540249cbb7e08d"
GIST_API_URL = f"https://api.github.com/gists/{GIST_ID}"
ARCHIVE_GIST_ID = "6c1ad65c3ac11282fed669614a12c4a5"
ARCHIVE_GIST_API_URL = f"https://api.github.com/gists/{ARCHIVE_GIST_ID}"

FORTNITE_APP_PATH = "/Applications/Fortnite.app"
PROVISION_URL = "https://github.com/isacucho/FnMacAssistant/raw/main/files/embedded.mobileprovision"

# Controls which part of the container is symlinked.
# "" = Entire Container (default, best for external drives)
# "Data" = The Data folder
# "Data/Documents/FortniteGame" = The game data folder
SYMLINK_TARGET_SUBPATH = "Data/Documents/FortniteGame"

REFRESH_ICON_BASE64 = """
R0lGODlhEAAQAMQAAO/v7+zs7OLg4N/f3+Li4uDg4N3d3ejo6OHh4d7e3ubm5t3d3eHh4d/f39/f
3+Dg4OHh4ejo6N3d3d7e3uLi4t3d3eDg4OHh4ejo6N3d3eHh4QAA
ACH5BAEAABwALAAAAAAQABAAAAVRYCSOZGl+ZQpCZJrvqTQiVq7vdYJgsDofD8SYJCKfT0fEQPD9
fYCFEQzQeB5oOgoRUKjdbrfcrnY7nZ7P63O4XGy3u2y1u8PhcLi7XC6Hw+Hw+n0BFiYBLCMhIQA7
"""
