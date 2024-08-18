from dataclasses import dataclass

from encoder import encode_basic_type_strings


@dataclass
class Test:
    test: str
    snake: list


@dataclass
class Venom:
    test_struct: Test


from dataclasses import dataclass
from typing import Any

from erlport.erlang import set_decoder, set_encoder
from erlport.erlterms import Atom, Map

from venomous import VenomousTrait, decode_basic_types_strings


@dataclass
class VenomStruct(VenomousTrait, Venom):
    __struct__: Atom = Atom(b"Elixir.VenomousTest.Venom")


@dataclass
class TestStruct(VenomousTrait, Test):
    __struct__: Atom = Atom(b"Elixir.VenomousTest.TestStruct")


venomous_structs = {
    Atom(b"Elixir.VenomousTest.Venom"): VenomStruct,
    Atom(b"Elixir.VenomousTest.TestStruct"): TestStruct,
}


def encoder(value: Any) -> Any:
    if isinstance(value, dict):
        return {encoder(key): encoder(value) for key, value in value.items()}
    if isinstance(value, (list, tuple, set)):
        return type(value)(encoder(item) for item in value)

    if isinstance(value, Venom):
        return VenomStruct.from_dict(value.__dict__).into_erl()
    if isinstance(value, Test):
        return TestStruct.from_dict(value.__dict__).into_erl()

    return encode_basic_type_strings(value)


def decoder(value: Any) -> Any:

    if isinstance(value, (Map, dict)):
        if struct := value.get(Atom(b"__struct__")):
            return venomous_structs[struct].from_dict(value, venomous_structs)
        return {decoder(key): decoder(val) for key, val in value.items()}
    elif isinstance(value, (set, list, tuple)):
        return type(value)(decoder(_val) for _val in value)

    return decode_basic_types_strings(value)


def erl_encode():
    set_encoder(encoder)
    set_decoder(decoder)
    return Atom(b"ok")


def test_venomous_trait(test):
    [test, abc] = test
    test = test[0]["x"]

    return [Venom(test_struct=test), abc]
