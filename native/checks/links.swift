import SwiftUI

// Compile this with the conversationLinks helper from Chat.swift, using the
// macOS SDK. No app, network, microphone or realtime session is started.
let text = "Read https://example.com/a. <img src=x> javascript:alert(1) https://example.org/?a=1&b=2"
let result = conversationLinks(text)
assert(String(result.characters) == text)
let urls = result.runs.compactMap { $0.link?.absoluteString }
assert(urls == ["https://example.com/a", "https://example.org/?a=1&b=2"], "\(urls)")
assert(conversationLinks("mailto:a@example.com file:///tmp/test").runs.allSatisfy { $0.link == nil })
let unicode = conversationLinks("こんにちは 👋 https://example.com/ café")
assert(String(unicode.characters) == "こんにちは 👋 https://example.com/ café")
assert(unicode.runs.compactMap { $0.link?.absoluteString } == ["https://example.com/"])
print("PASS: native literal text, web links, unsafe schemes and Unicode ranges")
