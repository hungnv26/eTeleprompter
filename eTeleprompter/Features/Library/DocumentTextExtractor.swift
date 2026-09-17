import Foundation
import Compression
import PDFKit
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// Turns a user-picked document into plain text for a script.
///
/// Supported everywhere: PDF (PDFKit), .docx (a zip whose `word/document.xml`
/// holds the text — parsed here directly, no third-party library), .txt,
/// .md and .rtf. Legacy binary .doc is a proprietary format with no public
/// parser on iOS; it is supported on macOS through AppKit and reported
/// honestly as unsupported on iOS rather than half-decoded.
enum DocumentTextExtractor {

    enum ImportError: LocalizedError {
        case unsupportedType(String)
        case legacyDocNotSupportedHere
        case unreadable
        case noText

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let ext):
                return "“.\(ext)” files can’t be imported. Use PDF, Word (.docx), text or RTF."
            case .legacyDocNotSupportedHere:
                return "Legacy Word (.doc) files can only be imported on a Mac. Save the file as .docx or PDF and try again."
            case .unreadable:
                return "The file couldn’t be read."
            case .noText:
                return "No text was found in the file."
            }
        }
    }

    static let supportedTypes: [UTType] = [
        .pdf, .plainText, .text, .rtf,
        UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("com.microsoft.word.doc"),
        UTType("net.daringfireball.markdown"),
    ].compactMap { $0 }

    /// Filename without extension, for a new script's title.
    static func suggestedTitle(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "Imported Script" : name
    }

    /// Extracts the document's text. Handles security-scoped URLs from the
    /// file importer itself.
    static func text(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        let raw: String
        switch ext {
        case "pdf":           raw = try pdfText(url)
        case "docx":          raw = try docxText(url)
        case "doc":           raw = try legacyDocText(url)
        case "rtf":           raw = try rtfText(url)
        case "txt", "md", "markdown", "text":
            raw = try plainText(url)
        default:
            // Trust the declared type over the extension if the extension is odd.
            if let type = UTType(filenameExtension: ext), type.conforms(to: .plainText) {
                raw = try plainText(url)
            } else {
                throw ImportError.unsupportedType(ext.isEmpty ? "?" : ext)
            }
        }

        let cleaned = normalise(raw)
        guard !cleaned.isEmpty else { throw ImportError.noText }
        return cleaned
    }

    // MARK: Formats

    private static func plainText(_ url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        // UTF-8 first; fall back to the most common legacy encodings.
        for enc in [String.Encoding.utf8, .utf16, .windowsCP1252, .isoLatin1] {
            if let s = String(data: data, encoding: enc) { return s }
        }
        throw ImportError.unreadable
    }

    private static func rtfText(_ url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url),
              let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil)
        else { throw ImportError.unreadable }
        return attr.string
    }

    private static func pdfText(_ url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else { throw ImportError.unreadable }
        var out = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let s = page.string {
                out += s
                out += "\n\n"
            }
        }
        return out
    }

    private static func legacyDocText(_ url: URL) throws -> String {
        #if canImport(AppKit)
        guard let data = try? Data(contentsOf: url),
              let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.docFormat],
                documentAttributes: nil)
        else { throw ImportError.unreadable }
        return attr.string
        #else
        throw ImportError.legacyDocNotSupportedHere
        #endif
    }

    /// .docx = zip archive; the body text lives in word/document.xml as
    /// <w:p> paragraphs containing <w:t> text runs.
    private static func docxText(_ url: URL) throws -> String {
        guard let archive = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        guard let xml = ZipReader.entry(named: "word/document.xml", in: archive) else {
            throw ImportError.unreadable
        }
        let parser = WordXMLTextParser()
        return parser.parse(xml)
    }

    // MARK: Cleanup

    /// Collapses runaway blank lines and trims; keeps paragraph breaks.
    private static func normalise(_ s: String) -> String {
        let unified = s.replacingOccurrences(of: "\r\n", with: "\n")
                       .replacingOccurrences(of: "\r", with: "\n")
        var out: [String] = []
        var blank = 0
        for line in unified.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                blank += 1
                if blank <= 1 { out.append("") }
            } else {
                blank = 0
                out.append(t)
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Minimal zip reader (enough for OOXML)

/// Reads one stored or deflated entry out of a zip archive by walking the
/// central directory. Only what .docx needs; no encryption, no zip64.
enum ZipReader {
    private static func u16(_ d: Data, _ i: Int) -> Int {
        Int(d[d.startIndex + i]) | Int(d[d.startIndex + i + 1]) << 8
    }
    private static func u32(_ d: Data, _ i: Int) -> Int {
        u16(d, i) | u16(d, i + 2) << 16
    }

    static func entry(named wanted: String, in d: Data) -> Data? {
        // End-of-central-directory record: scan back for its signature.
        guard d.count >= 22 else { return nil }
        var eocd = -1
        var i = d.count - 22
        while i >= max(0, d.count - 22 - 65_535) {
            if u32(d, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        let entries = u16(d, eocd + 10)
        var p = u32(d, eocd + 16)               // central directory offset

        for _ in 0..<entries {
            guard p + 46 <= d.count, u32(d, p) == 0x02014b50 else { return nil }
            let method   = u16(d, p + 10)
            let compSize = u32(d, p + 20)
            let fullSize = u32(d, p + 24)
            let nameLen  = u16(d, p + 28)
            let extraLen = u16(d, p + 30)
            let commLen  = u16(d, p + 32)
            let localOff = u32(d, p + 42)
            let name = String(data: d.subdata(in: (d.startIndex + p + 46)..<(d.startIndex + p + 46 + nameLen)),
                              encoding: .utf8) ?? ""
            if name == wanted {
                // Local header: name/extra lengths there may differ from the
                // central directory's, so read them again.
                guard localOff + 30 <= d.count, u32(d, localOff) == 0x04034b50 else { return nil }
                let lName  = u16(d, localOff + 26)
                let lExtra = u16(d, localOff + 28)
                let start  = localOff + 30 + lName + lExtra
                guard start + compSize <= d.count else { return nil }
                let payload = d.subdata(in: (d.startIndex + start)..<(d.startIndex + start + compSize))
                switch method {
                case 0:  return payload
                case 8:  return inflate(payload, expected: fullSize)
                default: return nil
                }
            }
            p += 46 + nameLen + extraLen + commLen
        }
        return nil
    }

    /// Raw DEFLATE (zip method 8) via the Compression framework.
    private static func inflate(_ src: Data, expected: Int) -> Data? {
        guard expected > 0 else { return Data() }
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: expected)
        defer { dst.deallocate() }
        let n = src.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(dst, expected, base, src.count, nil, COMPRESSION_ZLIB)
        }
        guard n > 0 else { return nil }
        return Data(bytes: dst, count: n)
    }
}

// MARK: - word/document.xml → text

/// Collects <w:t> runs; each </w:p> ends a paragraph, <w:tab/> and <w:br/>
/// become a tab and a line break.
private final class WordXMLTextParser: NSObject, XMLParserDelegate {
    private var out = ""
    private var inText = false

    func parse(_ xml: Data) -> String {
        let p = XMLParser(data: xml)
        p.delegate = self
        p.parse()
        return out
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "w:t":   inText = true
        case "w:tab": out += "\t"
        case "w:br", "w:cr": out += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { out += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch name {
        case "w:t": inText = false
        case "w:p": out += "\n"
        default: break
        }
    }
}
