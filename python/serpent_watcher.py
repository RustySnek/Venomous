import importlib
import importlib.util
import os
import pkgutil
import time

from erlport import erlang
from erlport.erlterms import Atom
from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer


class ChangeHandler(FileSystemEventHandler):
    def __init__(self, pid, paths):
        super().__init__()
        self.last_event_time = {}
        self.debounce_time = 0.5
        self.pid = pid
        self.paths = paths

    def on_modified(self, event):
        if event.src_path.endswith(".py"):
            self.handle_event("Changed", event.src_path)

    def on_created(self, event):
        if event.src_path.endswith(".py"):
            self.handle_event("Changed", event.src_path)

    def on_deleted(self, event):
        if event.src_path.endswith(".py"):
            self.handle_event("Deleted", event.src_path)

    def handle_event(self, action, path):
        current_time = time.time()
        if (
            path not in self.last_event_time
            or (current_time - self.last_event_time[path]) > self.debounce_time
        ):
            self.last_event_time[path] = current_time
            module_name = self.get_module_name(path)
            if module_name:
                try:
                    erlang.cast(self.pid, (Atom("reload".encode("utf-8")), module_name))
                except:
                    pass

    def get_module_name(self, path) -> str | None:
        if path.endswith(".py"):
            module_path = path[:-3]
            module_name = module_path.replace(os.path.sep, ".")
            for package in self.paths:
                package_name = package.replace(os.path.sep, ".")
                if module_name.startswith(package_name):
                    return module_name[
                        len(package.replace(os.path.sep, ".")) + 1 :
                    ]  # Remove package prefix
        return None


def watch_directories(paths, pid):
    paths = [path.decode() for path in paths]
    event_handler = ChangeHandler(pid, paths)
    observer = Observer()

    for directory in paths:
        if os.path.exists(directory):
            observer.schedule(event_handler, directory, recursive=True)

    observer.start()
    while True:
        time.sleep(5)
