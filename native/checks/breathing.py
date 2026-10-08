"""Run the real Foundation-only part of Breathing.swift: which words start
which exercise, and that the rhythm stays inside 0...1."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / "Arisu/Breathing.swift").read_text()
core = source[:source.index("// MARK: - end of Breath")].replace("import SwiftUI", "import Foundation")
check = r'''
let cases: [(String, Breath?)] = [
    ("Let's do a calm breathing exercise", .calm),
    ("breathing exercise please", .calm),
    ("Arisu, breathe with me, I'm so angry", .angry),
    ("I need a breathing exercise to activate", .activate),
    ("Help me breathe, I'm stressed", .calm),
    ("I was out of breath after the run", nil),
    ("I'm angry about the email", nil),
    ("", nil),
]
for (text, want) in cases { assert(Breath.asked(text) == want, "\(text) -> \(String(describing: Breath.asked(text)))") }
for b in Breath.allCases {
    for t in stride(from: 0.0, to: 40, by: 0.05) {
        let f = b.at(t).fill
        assert(f >= 0 && f <= 1, "\(b) fill \(f) at \(t)")
    }
    assert(b.at(0).step.word == "in")
}
print("PASS: breathing requests and rhythm")
'''
with tempfile.TemporaryDirectory(prefix="arisu-breathing-") as directory:
    test = Path(directory) / "main.swift"
    test.write_text(core + check)
    exe = Path(directory) / "check"
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(Path(directory) / "cache"),
                    str(test), "-o", str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
