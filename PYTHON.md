# Quick guide on erlport Python API
You can read more about this in the [erlport documentation](http://erlport.org/docs/python.html)

You can find the default data types mapping [here](http://erlport.org/docs/python.html#data-types-mapping)

## Creating an encoder/decoder
The function passed to the snake_manager's erlport_encoder should be a main function containing everything you will setup further.
```python
from erlport.erlang import set_decoder, set_encoder, set_message_handler
from erlport.erlterms import Atom

def main_encoder():
  set_decoder(decoder_func)
  set_encoder(encoder_func)
  set_message_handler(cast_handler_func)
  return Atom("ok".encode("utf-8"))
```
### An Encoder is a function that handles conversion PYTHON -> ELIXIR
Here is an example of encoding a simple class
> While this is possible, a better way would be to handle them in a function that returns this type directly.
```python
from dataclasses import dataclass
from erlport.erlterms import Atom

@dataclass
class Cat:
  name: str
  color: str
  favorite_snacks: list[str]

# By default erlport converts regular strings into charlists.
# We can handle most of the cases by encoding strings into utf-8 with a simple function like this.
def encode_basic_type_strings(data):
    if isinstance(data, str):
        return data.encode("utf-8")
    elif isinstance(data, list):
        return [encode_basic_type_strings(item) for item in data]
    elif isinstance(data, tuple):
        return tuple(encode_basic_type_strings(item) for item in data)
    elif isinstance(data, dict):
        return {key: encode_basic_type_strings(value) for key, value in data.items()}
    else:
        return data

def encoder(value: any):
  if isinstance(value, Cat):
    # We .__dict__ the class and normalize it's key,values.
    # Erlport will convert this dict into a Map
    return {
      Atom(encode_basic_type_strings(key)):   # Convert the keys to atoms
      encode_basic_type_strings(val)          # utf-8 Encode strings inside
      for key, val in value.__dict__.items()
    }
  # If none matches we encode strings, and return
  return encode_basic_type_strings(value)
```
### A decoder is a function that handles conversion ELIXIR -> PYTHON
Here is an example of decoding elixir's parameters
```python
from erlport.erlterms import Atom, Map

def decoder(value: any):
  # Elixir strings convert to bytes, we can decode them into utf-8 strings.
  if isinstance(value, bytes):
    return value.decode('utf-8')
  if isinstance(value, Map):
      # If its a Map custom type we decode bytes into utf-8 strings
      return {
            key.decode("utf-8"): [v.decode("utf-8") for v in val]
            for key, val in value.items()
      }
  # if none get caught we just return the raw inputs
  return value

```
