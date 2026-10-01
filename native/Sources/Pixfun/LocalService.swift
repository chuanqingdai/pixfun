import AppKit
import Foundation
import Security

struct ServiceError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

@MainActor
final class LocalService {
    private var process: Process?
    private var outputPipe: Pipe?
    private var log: FileHandle?
    private var buffer = Data()
    private var port: Int?
    private let token = LocalService.secret()
    private let nativeToken = LocalService.secret()
    private let session: URLSession
    let dataDirectory: URL
    private let images = NSCache<NSString, NSImage>()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration)
        if let test = ProcessInfo.processInfo.environment["PIXFUN_TEST_DATA_DIR"] {
            dataDirectory = URL(fileURLWithPath: test, isDirectory: true)
        } else {
            dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Pixfun/Library", isDirectory: true)
        }
    }
    private static func secret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    func start() async throws {
        // Older Electron builds predate the shared service lock.
        if ProcessInfo.processInfo.environment["PIXFUN_TEST_DATA_DIR"] == nil,
           NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.pixfun.desktop" }) {
            throw ServiceError(message: "Quit the previous Pixfun desktop app before opening this library.")
        }
        guard let resources = Bundle.main.resourceURL else { throw ServiceError(message: "App resources are missing.") }
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let logURL = dataDirectory.appendingPathComponent("native-service.log")
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        log = try FileHandle(forWritingTo: logURL)
        try log?.seekToEnd()
        let child = Process(), pipe = Pipe()
        child.executableURL = resources.appendingPathComponent("backend/pixfun-service/pixfun-service")
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = resources.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env["PIXFUN_DATA_DIR"] = dataDirectory.path
        env["PIXFUN_PUBLIC_DIR"] = resources.appendingPathComponent("public").path
        env["PIXFUN_EXAMPLE_DIR"] = resources.appendingPathComponent("public/examples/wild-alaska").path
        env["PIXFUN_AGENT_WORKER"] = resources.appendingPathComponent("agent-model-worker.py").path
        env["PIXFUN_SERVICE_TOKEN"] = token
        env["PIXFUN_NATIVE_TOKEN"] = nativeToken
        env["PIXFUN_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        env["PYTHONUNBUFFERED"] = "1"
        child.environment = env
        child.standardOutput = pipe
        child.standardError = log
        process = child; outputPipe = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            guard let owner = self else { return }
            Task { @MainActor in owner.consume(chunk) }
        }
        do { try child.run() } catch { stop(); throw error }
        for _ in 0..<300 {
            if port != nil {
                struct Health: Decodable { struct Tools: Decodable { var ffmpeg: Bool; var ffprobe: Bool }; var tools: Tools }
                let health: Health = try await get("/api/health")
                guard health.tools.ffmpeg && health.tools.ffprobe else { stop(); throw ServiceError(message: "The bundled media tools could not start.") }
                return
            }
            if !child.isRunning {
                let text = (try? String(contentsOf: logURL)) ?? ""
                stop()
                throw ServiceError(message: text.contains("already open") ? "This library is open in another Pixfun client. Quit it and retry." : "The local engine could not start. See native-service.log in the library folder.")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        stop()
        throw ServiceError(message: "The local engine took too long to start. Please retry.")
    }
    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               json["ready"] as? Bool == true, let number = json["port"] as? Int, (1...65535).contains(number) { port = number }
        }
    }
    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        if let child = process, child.isRunning {
            child.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if child.isRunning { kill(child.processIdentifier, SIGKILL) } }
        }
        process = nil; outputPipe = nil; port = nil; buffer.removeAll()
        try? log?.close(); log = nil
    }
    private func request(_ path: String, payload: [String: Any]? = nil, native: Bool = false) throws -> URLRequest {
        guard let port, path.hasPrefix("/"), !path.hasPrefix("//"), let url = URL(string: "http://127.0.0.1:\(port)" + path), url.host == "127.0.0.1", url.port == port else {
            throw ServiceError(message: "The local engine is unavailable.")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if native { request.setValue(nativeToken, forHTTPHeaderField: "X-Pixfun-Native") }
        if let payload {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    private func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw ServiceError(message: object?["error"] as? String ?? "The local request failed. Please retry.")
        }
        return data
    }
    func get<T: Decodable>(_ path: String, native: Bool = false) async throws -> T {
        try await JSONDecoder().decode(T.self, from: data(request(path, native: native)))
    }
    func post<T: Decodable>(_ path: String, _ payload: [String: Any], native: Bool = false) async throws -> T {
        try await JSONDecoder().decode(T.self, from: data(request(path, payload: payload, native: native)))
    }
    func update(_ path: String, _ payload: [String: Any]) async throws {
        struct Response: Decodable { var ok: Bool }
        let _: Response = try await post(path, payload)
    }
    func original(_ id: String) async throws -> URL {
        struct Response: Decodable { var path: String }
        let response: Response = try await get("/api/desktop/native/\(id)", native: true)
        return URL(fileURLWithPath: response.path)
    }
    func image(_ path: String) async -> NSImage? {
        if let image = images.object(forKey: path as NSString) { return image }
        guard let request = try? request(path), let bytes = try? await data(request), let image = NSImage(data: bytes) else { return nil }
        images.setObject(image, forKey: path as NSString, cost: bytes.count)
        return image
    }
}
