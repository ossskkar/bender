"""Compile/run production caption and tool paths with synthetic I/O only."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / "Arisu/Live.swift").read_text()
def method(name):
    marker = "    private " + ("static " if name == "isWork" else "") + "func " + name + "("
    start = source.index(marker)
    end = source.index("\n    }", start) + len("\n    }")
    return source[start:end].replace("private ", "", 1)
start = source.index("    static func isSilenceCommand(")
end = source.index("\n    }", start) + len("\n    }")
helpers = "import Foundation\nenum Live {\n" + method("isWork") + "\n" + source[start:end] + "\n}\n"
speech_start = source.index("    static func speechAnswer(")
speech_end = source.index("\n    }", speech_start) + len("\n    }")
helpers = helpers.replace("\n}\n", "\n" + source[speech_start:speech_end] + "\n}\n", 1)
links = (root / "Arisu/Chat.swift").read_text()
link_start = links.index("private let linkDetector")
link_end = links.index("\n}", links.index("func webLinks(", link_start)) + 2
helpers += links[link_start:link_end] + "\n"
helpers += source[source.index("struct VoiceInputs {"):]
fixture = (root / "checks/voice-input.swift").read_text().replace(
    "    PRODUCTION_METHODS", "\n".join(method(n) for n in ("runTool", "workDone", "speakReply", "rememberAnswer")))
with tempfile.TemporaryDirectory(prefix="arisu-native-input-") as directory:
    test = Path(directory) / "main.swift"; test.write_text(helpers + fixture)
    executable = Path(directory) / "check"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path",
                    str(Path(directory) / "cache"), str(test), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
