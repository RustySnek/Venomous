from dataclasses import dataclass
from typing import Dict

from erlport.erlterms import Atom, Map


def encode_basic_type_strings(data):
    if isinstance(data, str):
        return data.encode("utf-8")
    elif isinstance(data, (list, tuple, set)):
        return type(data)(encode_basic_type_strings(item) for item in data)
    elif isinstance(data, dict):
        return {
            encode_basic_type_strings(key): encode_basic_type_strings(value)
            for key, value in data.items()
        }
    elif isinstance(data, VenomousTrait):
        return data.into_erl()

    elif (_dic := getattr(data, "__dict__", None)) != None:
        return encode_basic_type_strings(_dic)
    else:
        return data


@dataclass
class VenomousTrait:
    __struct__: str

    @classmethod
    def from_dict(cls, erl_map: Map | Dict):
        self = cls()  # if you are missing __struct__, bad luck
        for key, val in erl_map.items():
            if isinstance(key, bytes):
                key = key.decode("utf-8")
            if getattr(self, key, None) and val == b"nil":
                continue
            if isinstance(val, VenomousTrait):
                val = val.into_erl()
            elif (_val := getattr(val, "__dict__", None)) != None:
                val = encode_basic_type_strings(_val)

            setattr(self, key, val)
        return self

    def into_erl(self) -> Dict:
        return {
            Atom(key.encode("utf-8")): encode_basic_type_strings(value)
            for key, value in self.__dict__.items()
        }
