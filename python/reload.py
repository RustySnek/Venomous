import importlib
import pkgutil
from types import ModuleType


def reload(module: bytes):
    for _importer, modname, _ispkg in pkgutil.iter_modules():
        module_name = module.decode()
        if module_name.startswith(modname):
            mod = importlib.import_module(module_name)
            if isinstance(mod, ModuleType):
                importlib.reload(mod)
                return
