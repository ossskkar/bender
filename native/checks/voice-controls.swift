import Foundation

// The runner extracts the actual helper from Live.swift; no copied regex.
for text in ["quiet", "QUIET!", "Arisu, please be quiet.", "stop talking", "silence", "okay, quiet please"] {
    assert(Live.isSilenceCommand(text), "command rejected: \(text)")
}
for text in ["The room is quiet.", "Is it quiet outside?", "not quiet", "quiet room", "I said quiet earlier", "", "quite", "quietly"] {
    assert(!Live.isSilenceCommand(text), "ordinary input silenced: \(text)")
}
print("PASS: native explicit silence commands and ordinary quiet mentions")
