import Foundation
import Testing
import NookCore
@testable import NookSheet

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) = { request in
        throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLErrorKey: request.url as Any])
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.response(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("Google Sheet source", .serialized)
struct GoogleSheetSourceTests {
    @Test("An HTTP failure is mapped without exposing the URL")
    func mapsHTTPFailure() async throws {
        StubURLProtocol.response = { request in
            let url = try #require(request.url)
            return (HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data())
        }
        let source = GoogleSheetSource(spreadsheetID: "SECRET", session: session())
        let space = try #require(Space.named("C1"))

        do {
            _ = try await source.load(spaces: [space])
            Issue.record("Expected an HTTP error")
        } catch let SheetLoadError.http(id, status) {
            #expect(id == "C1")
            #expect(status == 403)
        }
    }

    @Test("Tabs with different periods are rejected")
    func rejectsDifferentDates() async throws {
        let c1 = try #require(Space.named("C1"))
        let c2 = try #require(Space.named("C2"))
        StubURLProtocol.response = { request in
            let url = try #require(request.url)
            let secondTab = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "gid" })?.value == c2.sourceKey
            let date = secondTab ? "22/09/2026" : "21/09/2026"
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(Self.tabCSV(date: date).utf8))
        }
        let source = GoogleSheetSource(spreadsheetID: "TEST", session: session())

        await #expect(throws: SheetLoadError.self) {
            try await source.load(spaces: [c1, c2])
        }
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func tabCSV(date: String) -> String {
        var lines = [",Room",",Period",",\(date)",",MONDAY"]
        lines.append(contentsOf: SheetGrid.slots.map { "\($0)," })
        return lines.joined(separator: "\n")
    }
}
