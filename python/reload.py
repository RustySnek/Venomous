import importlib
import pkgutil
from types import ModuleType


def decode_module_name(module: str | bytes):
    if isinstance(module, bytes):
        return module.decode()
    elif isinstance(module, str):
        return module
    else:
        raise Exception("Could not decode module name properly.")


def reload(module: str | bytes):
    for _importer, modname, _ispkg in pkgutil.iter_modules():
        module_name = decode_module_name(module)
        if module_name.startswith(modname):
            mod = importlib.import_module(module_name)
            if isinstance(mod, ModuleType):
                importlib.reload(mod)
                return
