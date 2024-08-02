import importlib
import os
import pkgutil
import time

from erlport import erlang
from erlport.erlterms import Atom
from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

PACKAGE_PATHS = set()


def _is_forbidden(name: str):
    return name.startswith("erlport") or name == "this"


def _set_package_paths():
    global PACKAGE_PATHS
    for module_info in pkgutil.iter_modules():
        try:
            if _is_forbidden(module_info.name):
                continue
            module = importlib.import_module(module_info.name)
            file = module.__file__
            if file:
                module_path = os.path.dirname(file)
                PACKAGE_PATHS.add(module_path)
        except:
            continue


class ChangeHandler(FileSystemEventHandler):
    def __init__(self, pid):
        super().__init__()
        self.last_event_time = {}
        self.debounce_time = 0.5
        self.pid = pid

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
            for package in PACKAGE_PATHS:
                if module_name.startswith(package.replace(os.path.sep, ".")):
                    return module_name[
                        len(package.replace(os.path.sep, ".")) + 1 :
                    ]  # Remove package prefix
        return None


def watch_directories(pid):
    _set_package_paths()
    event_handler = ChangeHandler(pid)
    observer = Observer()

    for directory in PACKAGE_PATHS:
        if os.path.exists(directory):
            observer.schedule(event_handler, directory, recursive=True)

    observer.start()
    while True:
        time.sleep(5)
