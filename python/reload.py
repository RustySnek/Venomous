import importlib
import pkgutil
from types import ModuleType


def reload(module: bytes):
    for _importer, modname, _ispkg in pkgutil.iter_modules():
        if modname == module.decode():
            mod = importlib.import_module(modname)
            if isinstance(mod, ModuleType):
                importlib.reload(mod)
                print("reloaded", mod)
            else:
                print("failed", mod)
