"""
Provides `VenomousTrait` used for simplification of conversion between elixir structs and classes
"""

from dataclasses import dataclass
from typing import Any, Dict

from erlport.erlterms import Atom, Map


def encode_basic_type_strings(data: Any):
    """
    encodes str into utf-8 bytes
    handles VenomousTrait classes into structs
    converts non VenomousTrait classes into .__dict__
    """
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


def decode_basic_types_strings(data):
    """
    decodes bytes into utf-8 strings
    """
    if isinstance(data, bytes):
        return data.decode("utf-8")
    elif isinstance(data, dict):
        return {
            decode_basic_types_strings(key): decode_basic_types_strings(val)
            for key, val in data.items()
        }
    elif isinstance(data, (list, set, tuple)):
        return type(data)(decode_basic_types_strings(_val) for _val in data)

    return data


@dataclass
class VenomousTrait:
    """
    Inheritable class, provides function for struct/class conversion
    """

    __struct__: str

    @classmethod
    def from_dict(cls, erl_map: Map | Dict, structs: Dict = {}):
        """
        returns object with attrs from given Map/dict
        """
        self = cls()  # if you are missing __struct__, bad luck
        for key, val in erl_map.items():
            if isinstance(key, bytes):
                key = key.decode("utf-8")
            if getattr(self, key, None) and val == b"nil":
                continue
            if isinstance(val, bytes):
                val = val.decode("utf-8")
            if structs:

                if (
                    isinstance(val, Map)
                    and (_val := val.get(Atom(b"__struct__"), None)) != None
                ):
                    val = structs[_val].from_dict(val)
                elif isinstance(val, Map):
                    val = decode_basic_types_strings(val)

            elif isinstance(val, VenomousTrait):
                val = val.into_erl()
            elif (_val := getattr(val, "__dict__", None)) != None:
                val = encode_basic_type_strings(_val)

            setattr(self, key, val)
        return self

    def into_erl(self) -> Dict:
        """
        converts self into erlang-like Map
        """
        return {
            Atom(key.encode("utf-8")): encode_basic_type_strings(value)
            for key, value in self.__dict__.items()
        }
