"""Check the production microphone action with synthetic call state, without audio."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Arisu/Pet.swift").read_text()
start = source.index("    func toggleMicrophone()")
end = source.index("\n    }", start) + len("\n    }")
fixture = """
final class Live { var muted = false }
final class Pet {
    var running = false
    let live = Live()
    var starts = 0
    func begin() { running = true; starts += 1 }
""" + source[start:end] + """
}
let pet = Pet()
pet.toggleMicrophone()
precondition(pet.running && !pet.live.muted && pet.starts == 1)
pet.toggleMicrophone()
precondition(pet.running && pet.live.muted && pet.starts == 1)
pet.toggleMicrophone()
precondition(pet.running && !pet.live.muted && pet.starts == 1)
// Backgrounding ends the call. A previously muted call must restart unmuted.
pet.running = false
pet.live.muted = true
pet.toggleMicrophone()
precondition(pet.running && !pet.live.muted && pet.starts == 2)
print("PASS: microphone starts stopped calls, mutes/unmutes live calls, restarts after background")
"""
with tempfile.TemporaryDirectory(prefix="arisu-microphone-") as directory:
    directory = Path(directory)
    script = directory / "main.swift"
    script.write_text(fixture)
    executable = directory / "check"
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(directory / "cache"),
                    str(script), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
