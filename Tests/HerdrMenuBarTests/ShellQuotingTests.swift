import XCTest
@testable import HerdrMenuBar

final class ShellQuotingTests: XCTestCase {
    func testQuotesPlainString() {
        XCTAssertEqual(ShellQuoting.quoted("abc"), "'abc'")
    }

    func testQuotesEmptyString() {
        XCTAssertEqual(ShellQuoting.quoted(""), "''")
    }

    func testEscapesEmbeddedSingleQuote() {
        XCTAssertEqual(ShellQuoting.quoted("w'12"), "'w'\\''12'")
    }

    func testShellMetacharactersStayLiteral() {
        let dangerous = "p1; rm -rf ~ && echo $HOME `id`"
        let quoted = ShellQuoting.quoted(dangerous)

        XCTAssertEqual(quoted, "'\(dangerous)'")
        // The escaped form must not contain an unescaped semicolon outside quotes.
        XCTAssertFalse(quoted.hasPrefix("p1;"))
    }

    func testValueWithSingleQuoteRoundTripsThroughSh() throws {
        let value = "w3Y:p1;2 it's"
        let script = "printf %s \(ShellQuoting.quoted(value))"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(String(decoding: data, as: UTF8.self), value)
        XCTAssertEqual(process.terminationStatus, 0)
    }

    // MARK: - Jump command assembly

    func testJumpShellCommandQuotesPaneID() throws {
        guard let herdr = Executables.locate("herdr") else {
            throw XCTSkip("herdr is not installed; the command shape cannot be checked")
        }

        let command = try XCTUnwrap(
            Notifier.jumpShellCommand(paneID: "w3Y:p12; touch /tmp/pwned", frontmost: nil)
        )

        XCTAssertTrue(command.hasPrefix("\(ShellQuoting.quoted(herdr)) agent focus '"))
        XCTAssertTrue(command.contains("w3Y:p12; touch /tmp/pwned'"))
    }

    func testJumpShellCommandReturnsNilWithoutHerdr() throws {
        let command = Notifier.jumpShellCommand(paneID: "p1", frontmost: nil)
        if Executables.locate("herdr") == nil {
            XCTAssertNil(command)
        } else {
            XCTAssertNotNil(command)
        }
    }
}
