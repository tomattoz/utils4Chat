//  Created by Ivan Kh on 11.02.2026.

import Foundation

extension AsyncThrowingStream<String, Error> {
    init(_ src: AsyncThrowingStream<Data, Error>) {
        self.init { continuation in
            Task {
                do {
                    var prefix = Data()

                    for try await chunk in src {
                        var data = Data()

                        if !prefix.isEmpty {
                            data.append(prefix)
                            prefix.removeAll(keepingCapacity: true)
                        }

                        data.append(chunk)

                        guard !data.isEmpty else { continue }

                        var decoded: String? = nil
                        var tempData = data
                        var nextPrefix = Data()

                        // Limit the maximum number of bytes to move to avoid pathological loops
                        // UTF-8 code points are up to 4 bytes
                        for _ in 0..<4 {
                            decoded = String(data: tempData, encoding: .utf8)
                            
                            guard decoded == nil else { break }
                            guard !tempData.isEmpty else { break }
                            
                            let lastByte = tempData.removeLast()
                            nextPrefix.insert(lastByte, at: 0)
                        }

                        if let decoded {
                            if !decoded.isEmpty {
                                continuation.yield(decoded)
                            }

                            prefix = nextPrefix
                        }
                        else {
                            prefix = data
                        }
                    }

                    if !prefix.isEmpty {
                        if let decoded = String(data: prefix, encoding: .utf8),
                           !decoded.isEmpty {
                            continuation.yield(decoded)
                        }
                        else {
                            assertionFailure()
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
