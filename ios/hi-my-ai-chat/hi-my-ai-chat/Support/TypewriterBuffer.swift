import Foundation

actor TypewriterBuffer {
    private let pair = AsyncStream.makeStream(of: String.self)

    func stream() -> AsyncStream<String> {
        pair.stream
    }

    func enqueue(_ text: String) {
        guard text.isEmpty == false else { return }

        for character in text {
            pair.continuation.yield(String(character))
        }
    }

    func finish() {
        pair.continuation.finish()
    }
}
