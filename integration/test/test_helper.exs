postgres_exclusions = if System.get_env("JIDO_MESSAGING_POSTGRES_URL"), do: [], else: [:postgres]
ExUnit.start(capture_log: true, exclude: [:live | postgres_exclusions])
