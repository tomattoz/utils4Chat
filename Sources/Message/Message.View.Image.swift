//  Created by Ivan Khvorostinin on 08.04.2025.

import SwiftUI
import UniformTypeIdentifiers
import Combine
import QuickLook
import Utils9Client
import Utils9

private enum ImageError: Error, LocalizedError {
    case unableToGenerate
    
    var errorDescription: String? {
        switch self {
        case .unableToGenerate: "Unable to generate image. Please try again later."
        }
    }
}

extension Message {
    class ImageViewModel: ObservableObject {
        @Published var data: Message.Image
        @Published var item: Message.ImageStore.Image?
        @Published var loaded: Bool = false
        @Published var animateImageAppearance = false
        @Published var animateProgressAppearance = false
        let message: Message.Model
        let store: Message.ImageStore
        private var loadingBag: AnyCancellable?
        private var bag = [AnyCancellable]()

        init(store: Message.ImageStore, message: Message.Model, data: Message.Image) {
            self.message = message
            self.data = data
            self.store = store
            
            message.content.publisher
                .throttle(for: .seconds(0.5), scheduler: RunLoop.main, latest: true)
                .sink { [weak self] result in
                    self?.apply(loaded: true)
                } receiveValue: { [weak self] content in
                    self?.apply(loaded: false)
                }.store(in: &bag)

            apply(loaded: false)
        }
        
        func apply(loaded: Bool) {
            if let newData = message.content.imageData, self.data != newData {
                self.data = newData
            }
            
            if let url = data.url, item == nil {
                Task{ @MainActor in
                    loadingBag = await store.load(url: url, for: message).sink {
                        self.item = $0
                        self.loaded = loaded
                    }
                }
            }

            else if let url = data.url, item?.loaded != true {
                Task{ @MainActor in
                    let item = await store.image(remote: url)
                    
                    if self.item?.loaded != true && item?.loaded == true {
                        self.item = item
                        self.loaded = loaded
                    }
                }
            }
            else {
                self.loaded = loaded
            }
        }
    }
}

extension Message {
    struct ImageView: View {
        @StateObject var vm: ImageViewModel
        @State private var previewURL: URL?
        @State private var showSavePanel = false
        
        init(store: ImageStore, message: Message.Model, data: Message.Image) {
            _vm = .init(wrappedValue: .init(store: store, message: message, data: data))
        }
        
        var body: some View {
            VStack(spacing: 0) {
                if let item = vm.item, let image = item.image {
                    AppearanceAnimation(appearance: $vm.animateImageAppearance, duration: 0.25) {
                        Image(item: item, image: image)
                    }
                }
                
                else if let error = vm.item?.error {
                    Error(error: error)
                }
                
                else if vm.loaded {
                    Error(error: ImageError.unableToGenerate)
                }
                
                else if vm.message.content.mutable == true {
                    MessageImageProgress(vm: vm)
                }
                
                if let prompt = vm.data.prompt {
                    Prompt(prompt: prompt)
                }
            }
        }
        
        func Image(item: Message.ImageStore.Image, image: Image9) -> some View {
            SwiftUI.Image(image: image)
                .resizable()
                .scaledToFit()
                .messageImage()
                .quickLookPreview($previewURL)
                .onTapGesture {
                    previewURL = item.localURL
                }
                .onDrag {
                    let provider = NSItemProvider()
                    let uttype = item.contentType
                    
                    provider.suggestedName = item.suggestedName
                    
                    guard let data = tryLog({ try Data(contentsOf: item.localURL) }) else {
                        return provider
                    }
                    
                    provider.registerItem(forTypeIdentifier: uttype.identifier) { completion,_,_ in
                        completion?(data as NSSecureCoding, nil)
                    }
                    
                    return provider
                }
                .background {
                    #if os(macOS)
                    NSControlRepresentation() // prevent window dragging
                    #endif
                }
                .contextMenu {
                    Button {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([image])
                        #else
                        UIPasteboard.general.items = []
                        UIPasteboard.general.image = image
                        #endif
                    } label: {
                        Label("Copy", systemImage: "document.on.document")
                    }

                    Button {
                        showSavePanel = true
                    } label: {
                        Label("Save as...", systemImage: "square.and.arrow.down")
                    }
                }
                .fileExporter(isPresented: $showSavePanel,
                              document: try? URLFileDocument(item.localURL),
                              contentType: item.contentType,
                              defaultFilename: item.suggestedNameAndExtension,
                              onCompletion: { _ in })
        }
        
        func Error(error: Swift.Error) -> some View {
            ZStack {
                MessageImagePlaceholder()
                
                SwiftUI.Text(error.friendlyDescription)
                    .multilineTextAlignment(.center)
            }
        }
        
        func Prompt(prompt: String) -> some View {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    TextView(kind: vm.message.kind) {
                        SwiftUI.Text(LocalizedStringKey("**Prompt used to generate image:**"))
                    }
                    
                    TextView(kind: vm.message.kind) {
                        SwiftUI.Text(prompt)
                    }
                }
                
                Spacer()
            }
        }
    }
}

private struct MessageImagePlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(Color("message.image.placeholder.bg"))
            .frame(maxWidth: .infinity)
            .aspectRatio(contentMode: .fit)
            .messageImage()
    }
}

private struct AppearanceAnimation<Content: View>: View {
    @Binding var appearance: Bool
    let duration: TimeInterval
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        ZStack {
            content()
                .opacity(appearance ? 1 : 0) // Fade-in effect
        }
        .onAppear {
            if !appearance {
                withAnimation(.easeIn(duration: duration)) {
                    appearance = true
                }
            }
        }
    }
}

private struct MessageImageProgress: View {
    @ObservedObject var vm: Message.ImageViewModel

    var body: some View {
        AppearanceAnimation(appearance: $vm.animateProgressAppearance, duration: 0.75) {
            MessageImagePlaceholder()
            Spinner(color: Color("message.image.progress"))
            
            if progress > 0.01 {
                Text("\(Int(progress * 100))%")
            }
        }
    }
    
    var progress: Float {
        vm.data.progress ?? 0
    }
    
    var animation: Animation {
        Animation.linear(duration: 3.0)
            .repeatForever(autoreverses: false)
    }
}

private extension View {
    func messageImage() -> some View {
        self
            .cornerRadius(8)
            .padding(12)
    }
}

private extension Message.ImageStore.Image {
    var contentType: UTType {
        UTType(filenameExtension: localURL.path) ?? .webP
    }
    
    var suggestedName: String {
        "\(String.aispotImage) \(localURL.path.sha256short)"
    }
    
    var suggestedNameAndExtension: String {
        "\(suggestedName).\(localURL.pathExtension)"
    }
}
