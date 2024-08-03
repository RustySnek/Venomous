import importlib
import pkgutil
from types import ModuleType


def reload(module: bytes, logging: bool = True):
    for _importer, modname, _ispkg in pkgutil.iter_modules():
        if modname == module.decode():
            mod = importlib.import_module(modname)
            if isinstance(mod, ModuleType):
                importlib.reload(mod)
                if logging:
                    print("Reloaded:", mod)
                return
            elif logging:
                print("Failed to reload:", mod)
