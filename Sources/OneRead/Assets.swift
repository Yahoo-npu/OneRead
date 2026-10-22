import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Files owned by One Read, kept separate from the source document's original location.
enum AssetStore {
    static var dataDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["ONEREAD_DATA_DIR"] ?? (Bundle.main.object(forInfoDictionaryKey: "OneReadDataDirectory") as? String), path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if let path = UserDefaults.standard.string(forKey: DataLocation.preferenceKey), path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OneRead")
    }
    static func imageAspectRatio(at url: URL) -> Double? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Double, let height = properties[kCGImagePropertyPixelHeight] as? Double, width > 0, height > 0 { return width / height }
        if let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 { return image.size.width / image.size.height }
        return nil
    }
    static var root: URL { dataDirectory.appendingPathComponent("Assets", isDirectory: true) }
    static func directory(_ id: String, root: URL = root) -> URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return root.appendingPathComponent(id, isDirectory: true)
    }
    static func resource(_ name: String, assetID: String, root: URL = root) -> URL? {
        guard let directory = directory(assetID, root: root), !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.split(separator: "/").contains("..") else { return nil }
        let file = directory.appendingPathComponent(name).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(directory.standardizedFileURL.resolvingSymlinksInPath().path + "/") else { return nil }
        return file
    }
}

final class ImageArchive {
    let packageRoot: URL
    let output: URL
    var saved: [String: String] = [:]
    init(packageRoot: URL, output: URL) { self.packageRoot = packageRoot.standardizedFileURL; self.output = output }

    func image(_ source: String, relativeTo chapter: URL) throws -> String? {
        if let found = saved[chapter.path + "|" + source] { return found }
        let data: Data
        var isSVG = false
        if source.lowercased().hasPrefix("data:image/") {
            guard let separator = source.firstIndex(of: ","), source[..<separator].lowercased().hasSuffix(";base64"),
                  source.count < 28_000_000, let decoded = Data(base64Encoded: String(source[source.index(after: separator)...]), options: .ignoreUnknownCharacters) else { return nil }
            data = decoded; isSVG = source[..<separator].lowercased().contains("svg+xml")
        } else {
            guard let reference = URLComponents(string: source), reference.scheme == nil, reference.host == nil,
                  let path = reference.percentEncodedPath.removingPercentEncoding, !path.contains("\\") else { return nil }
            let base = path.hasPrefix("/") ? packageRoot : chapter.deletingLastPathComponent()
            let resolved = base.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path).standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(packageRoot.resolvingSymlinksInPath().path + "/"), FileManager.default.fileExists(atPath: resolved.path) else { return nil }
            let size = try resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20_000_000 else { return nil }
            data = try Data(contentsOf: resolved); isSVG = resolved.pathExtension.lowercased() == "svg"
        }
        let name = "image-\(saved.count)." + (isSVG ? "svg" : "png")
        let target = output.appendingPathComponent(name)
        if isSVG {
            guard let clean = SVGCleaner.clean(data) else { return nil }
            try clean.write(to: target, options: .atomic)
        } else {
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2600] as CFDictionary),
                  let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw ReadError.message("无法保存 EPUB 图片") }
        }
        saved[chapter.path + "|" + source] = name
        return name
    }
}

/// Only a static SVG subset is retained; scripts, external resources and event attributes are discarded.
final class SVGCleaner: NSObject, XMLParserDelegate {
    var result = ""
    var emitted: [Bool] = []
    var blockedDepth = 0
    let tags: Set<String> = ["svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text", "tspan", "defs", "linearGradient", "radialGradient", "stop", "clipPath", "mask", "use", "title", "desc"]
    let attributes: Set<String> = ["xmlns", "viewBox", "width", "height", "x", "y", "x1", "y1", "x2", "y2", "cx", "cy", "r", "rx", "ry", "d", "points", "fill", "fill-rule", "fill-opacity", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-dasharray", "stroke-opacity", "opacity", "transform", "id", "offset", "stop-color", "stop-opacity", "gradientUnits", "gradientTransform", "clip-path", "mask", "font-family", "font-size", "font-weight", "text-anchor", "dominant-baseline", "preserveAspectRatio", "href", "xlink:href", "xmlns:xlink"]
    static func escape(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
    static func clean(_ data: Data) -> Data? {
        let cleaner = SVGCleaner(); let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = cleaner
        guard parser.parse(), cleaner.result.hasPrefix("<svg") else { return nil }; return Data(cleaner.result.utf8)
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes attrs: [String: String]) {
        let allowed = blockedDepth == 0 && tags.contains(name)
        emitted.append(allowed)
        if !allowed { blockedDepth += 1; return }
        result += "<" + name
        for (key, value) in attrs.sorted(by: { $0.key < $1.key }) where attributes.contains(key) {
            if key == "href" || key == "xlink:href" { guard value.hasPrefix("#") else { continue } }
            if !key.hasPrefix("xmlns") && (value.lowercased().contains("url(") && !value.replacingOccurrences(of: " ", with: "").hasPrefix("url(#")) { continue }
            result += " \(key)=\"\(Self.escape(value))\""
        }
        result += ">"
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if blockedDepth == 0 { result += Self.escape(string) } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if emitted.popLast() == true { result += "</" + name + ">" } else { blockedDepth -= 1 }
    }
}
