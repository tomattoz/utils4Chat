//  Created by Ivan Kh on 11.12.2024.

import Foundation
import Combine
import AppKit
import Utils9AIAdapter
import Utils9
import Utils9Client

extension String {
    static let aispotImage = "AI Spot image"
}

extension Message.ImageStore {
    struct Image {
        let localURL: URL
        let image: NSImage?
        let error: Swift.Error?
        
        var loaded: Bool {
            image != nil || error != nil
        }
    }
}

public extension Message {
    actor ImageStore {
        private enum Error: Swift.Error, LocalizedError {
            case notFound(String)
            case load(String)
            
            var errorDescription: String? {
                switch self {
                case .notFound(let name): "Image not found (\(name))"
                case .load(let name): "Unable to load image (\(name))"
                }
            }
        }
        
        public static let shared = ImageStore()
        private let url: URL
        private var images: [String: Image] = [:]
        private var loading: [String: AnyPublisher<Image, Never>] = [:]

        init(_ url: URL = .appData.appendingPathComponent("image")) {
            self.url = url
        }
        
        func image(remote url: URL) -> Image? {
            return images[id(remote: url)]
        }
        
        private func id(remote url: URL) -> String {
            URL(fileURLWithPath: name(url))
                .deletingPathExtension()
                .lastPathComponent
        }
        
        private func id(local url: URL) -> String {
            url.deletingLastPathComponent().lastPathComponent
        }

        func load(url: URL) -> AnyPublisher<Image, Never> {
            let id = id(remote: url)

            if let publisher = loading[id] {
                return publisher
            }
            
            if let item = image(remote: url) {
                if item.image != nil {
                    return Just(item).eraseToAnyPublisher()
                }
                else {
                    return loadLocal(remote: url)
                }
            }
            else {
                return load(remote: url)
            }
        }
        
        public func load() {
            tryLog {
                for path in try FileManager.default.contentsOfDirectory(atPath: self.url.path) {
                    let folderURL = self.url.appendingPathComponent(path)
                    
                    guard !folderURL.isHidden else {
                        continue
                    }
                    
                    let fileURL = folderURL.appendingPathComponent(.aispotImage)
                    let id = id(local: fileURL)
                    
                    if !FileManager.default.isDirectory(folderURL) {
                        let oldFileURL = folderURL
                        let folderURL = folderURL.deletingPathExtension()
                        let fileURL = folderURL.appendingPathComponent(.aispotImage)
                        FileManager.default.tryCreateDirectoryIfNeeded(folderURL)
                        tryLog { try FileManager.default.moveItem(at: oldFileURL, to: fileURL) }
                    }
                    
                    images[id] = .init(localURL: fileURL, image: nil, error: nil)
                }
            }
        }

        func name(_ url: URL) -> String {
            if let result = nameV1(url) {
                return result
            }

            if let result = nameV2(url) {
                return result
            }

            log(error: "Unable to fetch name for DALLE image [\(url.absoluteString)]")
            return url.absoluteString.sha256 + ".png"
        }
        
        func nameV1(_ url: URL) -> String? {
            return url
                .query?.removingPercentEncoding?
                .split(separator: "&")
                .map { String($0) }
                .first { $0.hasPrefix("rscd=") }?
                .split(separator: "=")
                .map { String($0) }
                .last
        }
        
        func nameV2(_ url: URL) -> String? {
            var matched = false
            
            for component in url.pathComponents {
                if matched && UUID(uuidString: component) != nil {
                    return component + ".png"
                }
                
                if component == "files" {
                    matched = true
                }
            }
            
            return nil
        }
        
        func localURL(_ url: URL) -> URL {
            let name = name(url)
            
            var result = self.url.appendingPathComponent(name)
            let imageExtension = result.pathExtension

            result = result
                .deletingPathExtension()
                .appendingPathComponent(.aispotImage)
                .appendingPathExtension(imageExtension)
            
            return result
        }

        private func loadLocal(remote url: URL) -> AnyPublisher<Image, Never> {
            let localURL = self.localURL(url)
            return load(local: localURL)
        }
        
        private func load(local url: URL) -> AnyPublisher<Image, Never> {
            let id = id(local: url)
            let result = PassthroughSubject<Image, Never>()
            
            loading[id] = result.eraseToAnyPublisher()
            
            Task {
                await load(local: url, publisher: result)
            }
            
            return result.eraseToAnyPublisher()
        }
        
        private func load(local url: URL, publisher: PassthroughSubject<Image, Never>) async {
            let item: Image
            let id = id(local: url)
            
            if let nsImage = NSImage(contentsOf: url) {
                item = Image(localURL: url, image: nsImage, error: nil)
            }
            else {
                item = Image(localURL: url, image: nil, error: Error.load(id))
            }

            images[id] = item
            loading[id] = nil
            await publisher.complete(item)
        }
        
        private func load(remote url: URL) -> AnyPublisher<Image, Never> {
            let id = id(remote: url)
            let result = PassthroughSubject<Image, Never>()
            let localURL = self.localURL(url)

            loading[id] = result.eraseToAnyPublisher()
            
            Task {
                do {
                    let folderURL = localURL.deletingLastPathComponent()
                    FileManager.default.tryCreateDirectoryIfNeeded(folderURL)
                    
                    let localTmpURL = try await URLSession.shared.download(from: url).0
                    
                    try FileManager.default.moveItem(at: localTmpURL, to: localURL)
                    await load(local: localURL, publisher: result)
                }
                catch {
                    log(error)
                    await result.complete(.init(localURL: localURL,
                                                image: nil,
                                                error: error))
                }
            }

            return result.eraseToAnyPublisher()
        }
    }
}

private extension PassthroughSubject where Output == Message.ImageStore.Image, Failure == Never {
    func complete(_ output: Output) async {
        await MainActor.run {
            send(output)
            send(completion: .finished)
        }
    }
}
