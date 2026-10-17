import hashlib, json, re, subprocess, tempfile
from pathlib import Path
source = Path("mix.exs").read_text()
strict, count = re.subn(r'ignore_advisories:\s*\[[^]]*\]', 'ignore_advisories: []', source)
assert count == 1
with tempfile.TemporaryDirectory(prefix="jido-discord-strict-audit-") as directory:
    target = Path(directory)
    (target / "mix.exs").write_text(strict)
    (target / "mix.lock").write_bytes(Path("mix.lock").read_bytes())
    for name in ["deps", "_build", "config"]:
        if Path(name).exists(): (target / name).symlink_to(Path(name).resolve(), target_is_directory=True)
    import os
    environment = os.environ.copy()
    environment["JIDO_CHAT_PATH"] = str(Path("../jido_chat").resolve())
    print(json.dumps({"policy": "No ignored advisories", "original_mix_sha256": hashlib.sha256(source.encode()).hexdigest(), "strict_mix_sha256": hashlib.sha256(strict.encode()).hexdigest(), "lock_sha256": hashlib.sha256(Path("mix.lock").read_bytes()).hexdigest()}), flush=True)
    raise SystemExit(subprocess.run(["mix", "hex.audit"], cwd=target, env=environment).returncode)
