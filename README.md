![Venomous](https://github.com/RustySnek/Venomous/blob/master/assets/venomous_logo.png)

> A wrapper for managing concurrent [Erlport](http://erlport.org/) Python processes with ease.

[![CI](https://github.com/rustysnek/venomous/actions/workflows/elixir.yml/badge.svg)](https://github.com/rustysnek/venomous/actions/workflows/elixir.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/venomous)](https://hex.pm/packages/venomous)
[![Hex.pm](http://img.shields.io/hexpm/dt/venomous.svg)](https://hex.pm/packages/venomous)

Venomous is a wrapper around erlport python Ports, designed to simplify concurrent use. It focuses on dynamic extensibility, like spawning, reusing and killing processes on demand. Furthermore, unused processes get automatically killed by scheduled process which can be configured inside config.exs. Venomous core functions capture and handle :EXIT calls ensuring that all python process die with it and do not continue their execution.

## Installation
Add `:venomous` to your list of dependencies in `mix.exs`:
```elixir
def deps do
  [
    {:venomous, "~> 0.7.6"}
  ]
end
```
## Getting Started  
  Check the [documentation](https://hexdocs.pm/venomous) for more in-depth information.
  
  For custom type conversion see the [Handling Erlport API](https://github.com/RustySnek/Venomous/blob/master/PYTHON.md)

  > By default the python modules to load are kept inside PYTHONPATH envvar.
  > but I highly recommend setting them inside python_opts[:module_paths] for hot reloading comp.

  You can checkout examples [here](https://github.com/RustySnek/venomous-examples)

### Configure the SnakeManager options
  ```elixir
  config :venomous, :snake_manager, %{
    # Optional :erlport encoder/decoder for type conversion between elixir/python applied to all workers. The function may also include any :erlport callbacks from python api
    erlport_encoder: %{
      module: :my_encoder_module,
      func: :encode_my_snakes_please,
      args: []
    },
    # TTL whenever python process is inactive. Default: 15
    snake_ttl_minutes: 10,
    # Number of python workers that don't get cleared by SnakeManager when their TTL while inactive ends. Default: 10
    perpetual_workers: 1,
    # Interval for killing python processes past their ttl while inactive. Default: 60_000ms (1 min)
    cleaner_interval: 5_000,
    # reload module for hot reloading.
    # default is already provided inside venomous python/ directory
    reload_module: :reload,

    # Erlport python options
    python_opts: [
    module_paths: ["/path/to/my/modules", "/path/to/other/modules"], # List of paths to your python modules.
    cd: "/", # Change python's directory on spawn. Default is $PWD
    compressed: 0, # Can be set from 0-9. May affect performance. Read more on [Erlport documentation](http://erlport.org/docs/python.html#erlang-api)
    envvars: [SNAKE_VAR_ONE: "I'm a snake", SNAKE_VAR_TWO: "No, you are not"], # additional python process envvars
    packet_bytes: 4, # Size of erlport python packet. Default: 4 = max 4GB of data. Can also be set to 1 = 256 bytes or 2 = ? bytes if you are sure you won't be transfering a lot of data.
    python_executable: "/bin/python" # Change the path to python executable to use.
    ]
  }
  ```
### Enable the Hot reloading
  Requires watchdog python module, which can be installed with `mix venomous.watchdog install`.
  Currently only supports the SnakeManager's processes. Watches only directories specified in `module_paths`
  ```elixir
      config :venomous, :serpent_watcher, [
        enable: true, # Defaults to false
        logging: true, # log every hot reload. Default: true
        module: :serpent_watcher, # Provided by default
        func: :watch_directories, # Provided by default
        manager_pid: Venomous.SnakeManager, # Provided by default
        ]
  ```
### Configure the SnakeSupervisor and PetSnakeSupervisor (if needed) to start on application boot.
  ```elixir
  defmodule YourApp.Application do
    @moduledoc false

    use Application

    @doc false
    def start(_type, _args) do
      children = [
        {Venomous.SnakeSupervisor, [strategy: :one_for_one, max_restarts: 0, max_children: 50]},
        {Venomous.PetSnakeSupervisor, [strategy: :one_for_one, max_children: 10]} # not necessary
      ]
      opts = [strategy: :one_for_one, name: YourApp.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
  ```

## Quickstart
### Basic way to call python process
```elixir
alias Venomous.SnakeArgs
import Venomous

timeout = 1_000
args = SnakeArgs.from_params(:builtins, :sum, [[0,1,2,3,4,5]])

case python(args, python_timeout: timeout) do
    {:retrieve_error, msg} -> "No Snakes? #{inspect(msg)}"
    %{error: :timeout} -> "We timed out..."
    sum -> assert sum == 15
end

# or just use python!/3 which waits for the available snake.
timeout = :infinity
assert python!(args, python_timeout: timeout) == 15
```
### Concurrency and :EXIT signals
Venomous is designed with concurrency, as well as proper exits in mind.
```elixir
alias Venomous.SnakeArgs
import Venomous

# Venomous can handle as much concurrent python as you've setup
# in your snake_manager configuration. However the python! will
# wait for any process to free up in case none are available.
args = SnakeArgs.from_params(:time, :sleep, [0.5])
Enum.map(1..100, fn _ -> 
    Task.async(fn ->
        python!(args)
    end)
end) |> Task.await_many(5_000)

# You can view the spawned and ready snakes using the list_alive_snakes() 
list_alive_snakes() |> dbg
```
```elixir
alias Venomous.SnakeArgs
import Venomous

# Venomous kills the OS pid of the python process on :EXIT
# ensuring the process will not proceed with the execution further
Enum.map(1..200, fn _ ->
  {:ok, pid} =
    Task.start(fn ->
      SnakeArgs.from_params(:time, :sleep, [1000]) |> python!()
    end)

  pid
end)
|> Enum.each(fn pid ->
  Process.send_after(pid, {:EXIT, :snake_slithered_away}, 100)
end)

# We'll sleep to make sure all exits got sent.
Process.sleep(1_000)
assert list_alive_snakes() == []
```

## Struct/Class comp
Venomous provides an easy way to convert structs into classes and back with VenomousTrait class and `mix venomous.structs ...` task.
```
$ mix venomous.structs
Simple utility to create python elixir compatible classes.

        VenomousTrait class provides 2 functions: 
          - def from_dict(cls, erl_map: Map | Dict, structs: Dict = {}) -> cls
            # converts Erlport Map or a Dict into the object class
          - def into_erl(self, encoding_function \\ encode_basic_type_strings, *args \\ passed into the encoding function) -> Map
            # returns erlang compatible struct from self

           
        To create basic python classes and encode/decode functions based on structs: 
            - mix venomous.structs MyModule.MyStruct MyModule.MoreStructs ...

        To create extended classes depending on existing python class: 
            - mix venomous.structs MyModule.MyStruct:PythonClassName ...

        To create for all available structs inside an application
            - mix venomous.structs all my_application
```

You can see this used in the [struct_test.exs](https://github.com/RustySnek/Venomous/blob/master/test/struct_test.exs) and [test_venomous.py](https://github.com/RustySnek/Venomous/blob/master/python/test_venomous.py)

## Dev/Test REPL
Venomous provides dev/test only REPL
```elixir
$ iex -S mix test
Erlang/OTP 25 [erts-13.2.2.7] [source] [64-bit] [smp:16:2] [ds:16:2:10] [async-threads:1] [jit:ns]

Compiling 1 file (.ex)

15:45:10.953 [info] Started Snake Manager
 
15:45:10.954 [info] Started Pet Snake Manager
............
Finished in 12.9 seconds (0.00s async, 12.9s sync)
12 tests, 0 failures

Randomized with seed 961929
Interactive Elixir (1.16.2) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> test_struct = %VenomousTest.TestStruct{test: "123", snake: ["s","s","s"]}
%VenomousTest.TestStruct{test: "123", snake: ["s", "s", "s"]}
iex(2)> VenomousREPL.repl(inputs: [test_struct: test_struct])
Python REPL (module/outputs/pop/r (repeat)/exit): test_venomous
Python REPL (function): 
Available functions:

Test()
        name: self
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: undefined

        name: test
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'str'>

        name: snake
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'list'>
TestStruct()
        name: self
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: undefined

        name: test
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'str'>

        name: snake
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'list'>

        name: __struct__
        kind: POSITIONAL_OR_KEYWORD
        default: b'Elixir.VenomousTest.TestStruct'
        annotation: <class 'erlport.erlterms.Atom'>
Venom()
        name: self
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: undefined

        name: test_struct
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'test_venomous.Test'>
VenomStruct()
        name: self
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: undefined

        name: test_struct
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: <class 'test_venomous.Test'>

        name: __struct__
        kind: POSITIONAL_OR_KEYWORD
        default: b'Elixir.VenomousTest.Venom'
        annotation: <class 'erlport.erlterms.Atom'>
decoder()
        name: value
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: typing.Any
encoder()
        name: value
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: typing.Any
erl_encode()
        
test_venomous_trait()
        name: test
        kind: POSITIONAL_OR_KEYWORD
        default: undefined
        annotation: undefined
Python REPL (function): test_venomous_trait
Python REPL (arg 1): [{%{"x" => test_struct}}, "abc"]
Python REPL (arg 2): 
[lib/repl.ex:121: VenomousREPL.repl/1]
Venomous.python!(params) #=> [
  %VenomousTest.Venom{
    test_struct: %{
      "__struct__" => VenomousTest.TestStruct,
      "snake" => ["s", "s", "s"],
      "test" => "123"
    }
  },
  "abc"
]

Python REPL (module/outputs/pop/r (repeat)/exit): r
[lib/repl.ex:109: VenomousREPL.repl/1]
Venomous.python!(previous_args) #=> [
  %VenomousTest.Venom{
    test_struct: %{
      "__struct__" => VenomousTest.TestStruct,
      "snake" => ["s", "s", "s"],
      "test" => "123"
    }
  },
  "abc"
]

Python REPL (module/outputs/pop/r (repeat)/exit): outputs
[lib/repl.ex:96: VenomousREPL.repl/1]
outputs #=> [
  [
    %VenomousTest.Venom{
      test_struct: %{
        "__struct__" => VenomousTest.TestStruct,
        "snake" => ["s", "s", "s"],
        "test" => "123"
      }
    },
    "abc"
  ]
]

Python REPL (module/outputs/pop/r (repeat)/exit):
```
