{ pkgs, lib, config, inputs, ... }:

{

  packages = with pkgs; [
    elixir_1_16
    erlang
    elixir-ls
    python311
    python311Packages.pip
    nodePackages.pyright
    
 ] ++ lib.optionals pkgs.stdenv.isLinux (with pkgs; [inotify-tools]);

  env.LANG = "en_US.UTF-8";
  dotenv.enable = true;
  languages.python.enable = true;
  languages.python.venv.enable = true;

}
