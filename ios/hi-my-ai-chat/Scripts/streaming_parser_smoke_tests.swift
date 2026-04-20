import Foundation

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() == false {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func testMarkdownAndCodeBlocks() {
    let text = """
    ### Title

    - item 1
    - item 2

    ```swift
    print("hello")
    ```

    tail
    """

    let blocks = ChatMessageContentParser.parse(text: text, toolCalls: [])
    expect(blocks.count == 3, "expected markdown + code + markdown")

    guard case .markdown(let intro) = blocks[0] else {
        expect(false, "first block should be markdown")
        return
    }
    expect(intro.text.contains("### Title"), "markdown heading missing")

    guard case .code(let code) = blocks[1] else {
        expect(false, "second block should be code")
        return
    }
    expect(code.language == "swift", "code language should be swift")
    expect(code.code.contains("print(\"hello\")"), "code body missing")
    expect(code.isComplete, "code fence should be complete")

    guard case .markdown(let tail) = blocks[2] else {
        expect(false, "third block should be markdown")
        return
    }
    expect(tail.text.contains("tail"), "tail markdown missing")
}

func testIncompleteCodeFence() {
    let text = """
    Before

    ```json
    {"ok": true}
    """

    let blocks = ChatMessageContentParser.parse(text: text, toolCalls: [])
    expect(blocks.count == 2, "expected markdown + incomplete code")

    guard case .code(let code) = blocks[1] else {
        expect(false, "second block should be code")
        return
    }

    expect(code.language == "json", "code language should be json")
    expect(code.isComplete == false, "code fence should be incomplete")
}

func testToolCardsArePrepended() {
    let toolCalls = [
        ChatToolCall(
            id: "tool_1",
            name: "get_current_datetime",
            argumentsJSON: "{}",
            output: "{\"ok\":true}",
            status: .succeeded
        )
    ]

    let blocks = ChatMessageContentParser.parse(text: "after tool", toolCalls: toolCalls)
    expect(blocks.count == 2, "expected tool card + markdown")

    guard case .toolCall(let toolCall) = blocks[0] else {
        expect(false, "first block should be tool card")
        return
    }

    expect(toolCall.id == "tool_1", "tool card id mismatch")
}

@main
struct StreamingParserSmokeTests {
    static func main() {
        testMarkdownAndCodeBlocks()
        testIncompleteCodeFence()
        testToolCardsArePrepended()
        print("streaming parser smoke tests passed")
    }
}
