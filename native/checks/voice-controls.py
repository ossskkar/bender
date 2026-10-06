"""Run the actual Foundation-only native silence helper without launching audio."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / "Arisu/Live.swift").read_text()
start = source.index("    static func isSilenceCommand(")
end = source.index("\n    }", start) + len("\n    }")
helper = "import Foundation\nenum Live {\n" + source[start:end] + "\n}\n"
with tempfile.TemporaryDirectory(prefix="arisu-voice-controls-") as directory:
    test = Path(directory) / "main.swift"
    test.write_text(helper + (root / "checks/voice-controls.swift").read_text())
    executable = Path(directory) / "check"
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(Path(directory) / "cache"),
                    str(test), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
