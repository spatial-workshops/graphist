import Foundation
import Metal

nonisolated enum ShaderLibraryError: LocalizedError {
    case noShadersFound
    case compileFailed(file: String, message: String)
    case functionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noShadersFound:
            "No shaders found. Build with scripts/build-app.sh, or set GRAPHIST_SHADER_DIR to the repository's Shaders directory."
        case .compileFailed(let file, let message):
            "Shader compilation failed in \(file):\n\(message)"
        case .functionNotFound(let name):
            "Shader function '\(name)' was not found in any shader file."
        }
    }
}

/// Where shaders are loaded from.
nonisolated enum ShaderSource: CustomStringConvertible {
    /// Precompiled by the build script (fastest startup; used by packaged builds).
    case metallib(URL)
    /// `.metal` sources compiled at runtime. `live` sources are recompiled on scene reload.
    case sources(URL, live: Bool)

    var isLive: Bool {
        if case .sources(_, true) = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .metallib(let url): "metallib: \(url.lastPathComponent)"
        case .sources(_, let live): live ? "shaders: live source" : "shaders: bundled source"
        }
    }
}

/// All of the app's Metal shader functions, plus helpers for building pipelines.
///
/// Every `.metal` file under `Shaders/` ends up in here, so scenes look functions up
/// by name only. `#include "Something.h"` works for any header under `Shaders/`.
final class ShaderLibrary {
    let device: any MTLDevice
    let source: ShaderSource
    private let libraries: [any MTLLibrary]
    private var functionCache: [String: any MTLFunction] = [:]

    init(device: any MTLDevice, source: ShaderSource) throws {
        self.device = device
        self.source = source
        switch source {
        case .metallib(let url):
            libraries = [try device.makeLibrary(URL: url)]
        case .sources(let directory, _):
            libraries = try Self.compileSources(in: directory, device: device)
        }
    }

    // MARK: Lookup

    func function(named name: String) throws -> any MTLFunction {
        if let cached = functionCache[name] { return cached }
        for library in libraries {
            if let function = library.makeFunction(name: name) {
                functionCache[name] = function
                return function
            }
        }
        throw ShaderLibraryError.functionNotFound(name)
    }

    // MARK: Pipeline helpers

    /// Builds a render pipeline with a single color attachment.
    /// Use `configure` for anything beyond the basics (custom blend factors,
    /// extra attachments, vertex descriptors, ...).
    func makeRenderPipeline(
        label: String,
        vertex: String,
        fragment: String,
        pixelFormat: MTLPixelFormat,
        blend: PipelineBlend = .opaque,
        configure: ((MTLRenderPipelineDescriptor) -> Void)? = nil
    ) throws -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = try function(named: vertex)
        descriptor.fragmentFunction = try function(named: fragment)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        blend.apply(to: descriptor.colorAttachments[0])
        configure?(descriptor)
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func makeComputePipeline(_ name: String) throws -> any MTLComputePipelineState {
        try device.makeComputePipelineState(function: try function(named: name))
    }

    // MARK: Locating shaders

    /// Search order:
    ///   1. `GRAPHIST_SHADER_DIR` environment variable (live editing)
    ///   2. `Graphist.metallib` in the app bundle (normal packaged build)
    ///   3. `Shaders/` sources in the app bundle (build machine had no Metal toolchain)
    ///   4. The repository's `Shaders/` directory (running via `swift run` or Xcode)
    static func locateSource() -> ShaderSource? {
        let fileManager = FileManager.default
        func isDirectory(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        if let override = ProcessInfo.processInfo.environment["GRAPHIST_SHADER_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if isDirectory(url) { return .sources(url, live: true) }
        }
        if let metallib = Bundle.main.url(forResource: "Graphist", withExtension: "metallib") {
            return .metallib(metallib)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Shaders", isDirectory: true),
           isDirectory(bundled) {
            return .sources(bundled, live: false)
        }
        // This file lives at <repo>/Sources/Graphist/Engine/ShaderLibrary.swift.
        let repoShaders = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Engine
            .deletingLastPathComponent() // Graphist
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // <repo>
            .appendingPathComponent("Shaders", isDirectory: true)
        if isDirectory(repoShaders) { return .sources(repoShaders, live: true) }
        return nil
    }

    // MARK: Runtime compilation

    private static func compileSources(in directory: URL, device: any MTLDevice) throws -> [any MTLLibrary] {
        var metalFiles: [URL] = []
        var headers: [String: URL] = [:]
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                switch url.pathExtension {
                case "metal": metalFiles.append(url)
                case "h": headers[url.lastPathComponent] = url
                default: break
                }
            }
        }
        guard !metalFiles.isEmpty else { throw ShaderLibraryError.noShadersFound }

        let options = MTLCompileOptions()
        options.mathMode = .fast

        var libraries: [any MTLLibrary] = []
        for file in metalFiles.sorted(by: { $0.path < $1.path }) {
            var included = Set<String>()
            let source = try expandIncludes(in: file, headers: headers, included: &included)
            do {
                libraries.append(try device.makeLibrary(source: source, options: options))
            } catch {
                throw ShaderLibraryError.compileFailed(
                    file: file.lastPathComponent,
                    message: error.localizedDescription
                )
            }
        }
        return libraries
    }

    /// Runtime compilation has no include search path, so `#include "x.h"` is inlined
    /// here. `#line` directives keep compiler error locations accurate.
    private static func expandIncludes(
        in url: URL,
        headers: [String: URL],
        included: inout Set<String>
    ) throws -> String {
        let text = try String(contentsOf: url, encoding: .utf8)
        let name = url.lastPathComponent
        var output = ["#line 1 \"\(name)\""]
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if let header = quotedInclude(in: line) {
                let sibling = url.deletingLastPathComponent().appendingPathComponent(header)
                let resolved = FileManager.default.fileExists(atPath: sibling.path)
                    ? sibling
                    : headers[(header as NSString).lastPathComponent]
                if let resolved {
                    if included.insert(resolved.standardizedFileURL.path).inserted {
                        output.append(try expandIncludes(in: resolved, headers: headers, included: &included))
                    }
                    output.append("#line \(index + 2) \"\(name)\"")
                    continue
                }
            }
            output.append(line)
        }
        return output.joined(separator: "\n")
    }

    private static func quotedInclude(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#include") else { return nil }
        let parts = trimmed.components(separatedBy: "\"")
        return parts.count >= 3 ? parts[1] : nil
    }
}

/// Common blend configurations for `ShaderLibrary.makeRenderPipeline`.
enum PipelineBlend {
    case opaque
    /// Straight (non-premultiplied) alpha.
    case alpha
    /// Fragment outputs premultiplied color.
    case premultipliedAlpha
    /// src + dst — glows, particles, light.
    case additive

    func apply(to attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        switch self {
        case .opaque:
            attachment.isBlendingEnabled = false
            return
        case .alpha:
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        case .premultipliedAlpha:
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        case .additive:
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one
        }
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
    }
}
