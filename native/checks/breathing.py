"""Run the real Foundation-only part of Breathing.swift: the rhythm she is
told, and that the breath stays inside 0...1."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / "Arisu/Breathing.swift").read_text()
core = source[:source.index("// MARK: - end of Breath")].replace("import SwiftUI", "import Foundation")
check = r'''
assert(Breath.calm.rhythm == "in 4, hold 2, out 6", Breath.calm.rhythm)
for b in Breath.allCases {
    for t in stride(from: 0.0, to: 40, by: 0.05) {
        let f = b.at(t).fill
        assert(f >= 0 && f <= 1, "\(b) fill \(f) at \(t)")
    }
    assert(b.at(0).step.word == "in")
}
print("PASS: breathing rhythm")
'''
with tempfile.TemporaryDirectory(prefix="arisu-breathing-") as directory:
    test = Path(directory) / "main.swift"
    test.write_text(core + check)
    exe = Path(directory) / "check"
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(Path(directory) / "cache"),
                    str(test), "-o", str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
