import Darwin
import Foundation

enum UnixSocketError: LocalizedError {
    case socket(String)
    case connect(String)
    case write(String)
    case read(String)
    case malformedResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case let .socket(message): "无法创建 UNIX socket：\(message)"
        case let .connect(message): "无法连接 Clash Verge 控制接口：\(message)"
        case let .write(message): "无法写入控制接口：\(message)"
        case let .read(message): "无法读取控制接口：\(message)"
        case .malformedResponse: "控制接口返回了无法识别的响应。"
        case let .httpStatus(code, body): "控制接口 HTTP \(code)：\(body)"
        }
    }
}

struct UnixHTTPResponse {
    let statusCode: Int
    let body: Data
}

enum UnixHTTPClient {
    static func get(socketPath: String, path: String) async throws -> UnixHTTPResponse {
        try await send(socketPath: socketPath, method: "GET", path: path, body: nil)
    }

    static func put(
        socketPath: String,
        path: String,
        jsonBody: [String: String]
    ) async throws -> UnixHTTPResponse {
        let data = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
        return try await send(
            socketPath: socketPath,
            method: "PUT",
            path: path,
            body: data
        )
    }

    static func send(
        socketPath: String,
        method: String,
        path: String,
        body: Data?
    ) async throws -> UnixHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let response = try blockingSend(
                        socketPath: socketPath,
                        method: method,
                        path: path,
                        body: body
                    )
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func blockingSend(
        socketPath: String,
        method: String,
        path: String,
        body: Data?
    ) throws -> UnixHTTPResponse {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw UnixSocketError.socket(String(cString: strerror(errno)))
        }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else {
            throw UnixSocketError.connect("socket 路径过长")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            let raw = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self)
            raw.initialize(repeating: 0, count: capacity)
            for (index, byte) in pathBytes.enumerated() {
                raw[index] = CChar(bitPattern: byte)
            }
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard connected == 0 else {
            throw UnixSocketError.connect(String(cString: strerror(errno)))
        }

        var request = Data()
        request.append(Data("\(method) \(path) HTTP/1.1\r\n".utf8))
        request.append(Data("Host: localhost\r\n".utf8))
        request.append(Data("Accept: application/json\r\n".utf8))
        request.append(Data("Connection: close\r\n".utf8))
        if let body {
            request.append(Data("Content-Type: application/json\r\n".utf8))
            request.append(Data("Content-Length: \(body.count)\r\n".utf8))
        }
        request.append(Data("\r\n".utf8))
        if let body {
            request.append(body)
        }

        let didWrite = request.withUnsafeBytes { rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress else { return true }
            var sent = 0
            while sent < rawBuffer.count {
                let result = Darwin.write(
                    descriptor,
                    base.advanced(by: sent),
                    rawBuffer.count - sent
                )
                if result < 0 {
                    return false
                }
                sent += result
            }
            return true
        }
        guard didWrite else {
            throw UnixSocketError.write(String(cString: strerror(errno)))
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                response.append(buffer, count: count)
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                throw UnixSocketError.read(String(cString: strerror(errno)))
            }
        }
        guard let headerSeparator = response.range(of: Data("\r\n\r\n".utf8)) else {
            throw UnixSocketError.malformedResponse
        }
        let headerData = response.subdata(in: 0..<headerSeparator.lowerBound)
        var bodyData = response.subdata(
            in: headerSeparator.upperBound..<response.count
        )
        guard let headerText = String(data: headerData, encoding: .utf8),
              let statusLine = headerText.components(separatedBy: "\r\n").first else {
            throw UnixSocketError.malformedResponse
        }
        let headers = headerText
            .components(separatedBy: "\r\n")
            .dropFirst()
            .reduce(into: [String: String]()) { result, line in
                guard let separator = line.firstIndex(of: ":") else { return }
                let key = line[..<separator]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let value = line[line.index(after: separator)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                result[key] = value
            }
        if headers["transfer-encoding"]?
            .lowercased()
            .contains("chunked") == true {
            bodyData = try decodeChunkedBody(bodyData)
        }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
            throw UnixSocketError.malformedResponse
        }
        guard (200..<300).contains(statusCode) else {
            let message = String(data: bodyData, encoding: .utf8) ?? ""
            throw UnixSocketError.httpStatus(
                statusCode,
                String(message.prefix(300))
            )
        }
        return UnixHTTPResponse(statusCode: statusCode, body: bodyData)
    }

    private static func decodeChunkedBody(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        var cursor = 0
        var decoded = Data()
        while cursor < bytes.count {
            guard let lineEnd = crlfIndex(bytes, from: cursor) else {
                throw UnixSocketError.malformedResponse
            }
            let sizeLine = String(
                bytes: bytes[cursor..<lineEnd],
                encoding: .utf8
            ) ?? ""
            let sizeToken = sizeLine
                .split(separator: ";", maxSplits: 1)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let size = Int(sizeToken, radix: 16), size >= 0 else {
                throw UnixSocketError.malformedResponse
            }
            cursor = lineEnd + 2
            if size == 0 {
                return decoded
            }
            guard cursor + size <= bytes.count else {
                throw UnixSocketError.malformedResponse
            }
            decoded.append(contentsOf: bytes[cursor..<(cursor + size)])
            cursor += size
            guard cursor + 1 < bytes.count,
                  bytes[cursor] == 13,
                  bytes[cursor + 1] == 10 else {
                throw UnixSocketError.malformedResponse
            }
            cursor += 2
        }
        throw UnixSocketError.malformedResponse
    }

    private static func crlfIndex(_ bytes: [UInt8], from start: Int) -> Int? {
        guard start + 1 < bytes.count else { return nil }
        for index in start..<(bytes.count - 1) {
            if bytes[index] == 13, bytes[index + 1] == 10 {
                return index
            }
        }
        return nil
    }
}
