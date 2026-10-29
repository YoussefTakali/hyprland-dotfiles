# Nautilus: "Open in Kitty" in the right-click menu (on a folder, or on the empty space of the current folder).
# Nautilus's own "Open in Console" is hard-wired to Ptyxis; this adds kitty next to it. (2026-10-29)
import subprocess

from gi.repository import GObject, Nautilus


def _local_path(file_info):
    if file_info.get_uri_scheme() != "file":
        return None
    location = file_info.get_location()
    return location.get_path() if location else None


def _open(_menu, path):
    subprocess.Popen(["kitty", "--directory", path], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class OpenInKitty(GObject.GObject, Nautilus.MenuProvider):
    def get_file_items(self, files):
        if len(files) != 1 or not files[0].is_directory():
            return []
        path = _local_path(files[0])
        if not path:
            return []
        item = Nautilus.MenuItem(name="OpenInKitty::folder", label="Open in Kitty", tip=f"Open kitty in {path}")
        item.connect("activate", _open, path)
        return [item]

    def get_background_items(self, current_folder):
        path = _local_path(current_folder)
        if not path:
            return []
        item = Nautilus.MenuItem(name="OpenInKitty::here", label="Open in Kitty", tip=f"Open kitty in {path}")
        item.connect("activate", _open, path)
        return [item]
