import XCTest
@testable import eTeleprompter

/// Runs the extractor against real files: Word, RTF and legacy .doc produced
/// by macOS's own `textutil`, a PDF from the print system, and a hand-built
/// DEFLATE-compressed .docx that exercises the zip inflate path directly.
final class DocumentTextExtractorTests: XCTestCase {

    private func fixture(_ name: String) throws -> URL {
        let bundle = Bundle(for: DocumentTextExtractorTests.self)
        return try XCTUnwrap(bundle.url(forResource: name, withExtension: nil),
                             "missing fixture \(name)")
    }

    private func assertExtracts(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let text = try DocumentTextExtractor.text(from: fixture(name))
        XCTAssertTrue(text.contains("Good morning, everyone"), "\(name): opening line missing in: \(text.prefix(120))", file: file, line: line)
        XCTAssertTrue(text.contains("They struggle to deliver."), "\(name): last line missing", file: file, line: line)
        // paragraphs survive as separate lines
        XCTAssertGreaterThanOrEqual(text.components(separatedBy: "\n").count, 3, "\(name): paragraph breaks lost", file: file, line: line)
    }

    func testPlainText() throws { try assertExtracts("sample.txt") }
    func testRTF() throws       { try assertExtracts("sample.rtf") }
    func testPDF() throws       { try assertExtracts("sample.pdf") }
    func testWordDocx() throws  { try assertExtracts("sample.docx") }

    func testMinimalDeflatedDocxHandlesRunsTabsAndBreaks() throws {
        let text = try DocumentTextExtractor.text(from: fixture("minimal.docx"))
        XCTAssertTrue(text.contains("First paragraph with a\ttab inside."), "tab lost: \(text)")
        XCTAssertTrue(text.contains("Second paragraph split across runs."), "runs not joined: \(text)")
        XCTAssertTrue(text.contains("Line one\nline two via br."), "br lost: \(text)")
        XCTAssertEqual(text.components(separatedBy: "\n").count, 4, "expected 3 paragraphs + br: \(text)")
    }

    func testLegacyDoc() throws {
        #if os(macOS)
        try assertExtracts("sample.doc")
        #else
        XCTAssertThrowsError(try DocumentTextExtractor.text(from: fixture("sample.doc"))) { error in
            guard case DocumentTextExtractor.ImportError.legacyDocNotSupportedHere = error else {
                return XCTFail("expected legacyDocNotSupportedHere, got \(error)")
            }
        }
        #endif
    }

    func testSuggestedTitleStripsExtension() throws {
        XCTAssertEqual(DocumentTextExtractor.suggestedTitle(for: URL(fileURLWithPath: "/x/Keynote Draft.docx")), "Keynote Draft")
    }

    func testUnsupportedExtensionIsRejectedClearly() {
        let url = URL(fileURLWithPath: "/nonexistent/file.xyz")
        XCTAssertThrowsError(try DocumentTextExtractor.text(from: url)) { error in
            guard case DocumentTextExtractor.ImportError.unsupportedType(let ext) = error else {
                return XCTFail("expected unsupportedType, got \(error)")
            }
            XCTAssertEqual(ext, "xyz")
        }
    }

    func testFolderNamingSkipsTakenNumbers() {
        XCTAssertEqual(SidebarView.nextFreeFolderName(existing: []), "New Folder 1")
        XCTAssertEqual(SidebarView.nextFreeFolderName(existing: ["New Folder 1"]), "New Folder 2")
        XCTAssertEqual(SidebarView.nextFreeFolderName(existing: ["New Folder 1", "New Folder 2", "Ideas"]), "New Folder 3")
        XCTAssertEqual(SidebarView.nextFreeFolderName(existing: ["New Folder 2"]), "New Folder 1")
    }
}
