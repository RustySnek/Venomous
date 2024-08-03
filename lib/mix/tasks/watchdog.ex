defmodule Mix.Tasks.Venomous.Watchdog do
  use Mix.Task

  @moduledoc """
    Used for installing/uninstalling python watchdog module into python/ directory.
  """
  @shortdoc "Installs watchdog module into python/ dir"
  @github_repo "https://github.com/gorakhargosh/watchdog"
  @tag "v4.0.1"
  @path "#{File.cwd!()}/python"

  @impl Mix.Task
  def run(args) do
    case args do
      ["install"] -> install_watchdog(@github_repo, @tag)
      _ -> Mix.raise("Invalid arguments. Usage: install / uninstall")
    end
  end

  defp install_watchdog(repo, tag) do
    IO.puts("Cloning watchdog into #{@path}/watchdog ...")

    case System.cmd("git", ["clone", "-b", tag, "--single-branch", repo, "#{@path}/watchdog_repo"]) do
      {_output, 0} ->
        IO.puts("Cloned watchdog.")
        System.cmd("mv", ["#{@path}/watchdog_repo/src/watchdog", @path])
        IO.puts("Moved module into #{@path}")
        System.cmd("rm", ["-r", "#{@path}/watchdog_repo"])
        IO.puts("Removed cloned repo.")
        IO.puts("Successfully installed package.")

      {error, _exit_code} ->
        Mix.raise(error)
        Mix.raise("Failed to download")
    end
  end
end
