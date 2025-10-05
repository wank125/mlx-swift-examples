// Copyright 2024 Apple Inc.

import AVKit
import AsyncAlgorithms
import CoreImage
import MLX
import MLXLMCommon
import MLXVLM
import PhotosUI
import SwiftUI

#if os(iOS) || os(visionOS)
    typealias PlatformImage = UIImage
#else
    typealias PlatformImage = NSImage
#endif

let videoSystemPrompt =
    "Focus only on describing the key dramatic action or notable event occurring in this video segment. Skip general context or scene-setting details unless they are crucial to understanding the main action."
let imageSystemPrompt =
    "You are an image understanding model capable of describing the salient features of any image."

struct ContentView: View {

    @State var llm = VLMEvaluator()
    @Environment(DeviceStat.self) private var deviceStat

    @State private var selectedImage: PlatformImage? = nil {
        didSet {
            if selectedImage != nil {
                selectedVideoURL = nil
                player = nil
            }
        }
    }
    @State private var selectedVideoURL: URL? {
        didSet {
            if let selectedVideoURL {
                player = AVPlayer(url: selectedVideoURL)
                selectedImage = nil
            }
        }
    }
    @State private var showingImagePicker = false
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var player: AVPlayer? = nil

    private var currentImageURL: URL? {
        selectedImage == nil && selectedVideoURL == nil
            ? URL(
                string:
                    "https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/bee.jpg"
            ) : nil
    }

    var body: some View {
        VStack(alignment: .leading) {
            VStack(spacing: 8) {
                HStack {
                    Text(llm.modelInfo)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    if !llm.stat.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "speedometer")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text(llm.stat)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(8)
                    }
                }

                VStack {
                    if let player {
                        VideoPlayer(player: player)
                            .frame(height: 300)
                            .cornerRadius(12)
                    } else if let selectedImage {
                        Group {
                            #if os(iOS) || os(visionOS)
                                Image(uiImage: selectedImage)
                                    .resizable()
                            #else
                                Image(nsImage: selectedImage)
                                    .resizable()
                            #endif
                        }
                        .scaledToFit()
                        .cornerRadius(12)
                        .frame(height: 300)
                    } else if let imageURL = currentImageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(12)
                                    .frame(height: 200)
                            case .failure:
                                Image(systemName: "photo.badge.exclamationmark")
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }

                    HStack {
                        #if os(iOS) || os(visionOS)
                            PhotosPicker(
                                selection: $selectedItem,
                                matching: PHPickerFilter.any(of: [
                                    PHPickerFilter.images, PHPickerFilter.videos,
                                ])
                            ) {
                                Label("Select Image/Video", systemImage: "photo.badge.plus")
                            }
                            .onChange(of: selectedItem) {
                                Task {
                                    if let video = try? await selectedItem?.loadTransferable(
                                        type: TransferableVideo.self)
                                    {
                                        selectedVideoURL = video.url
                                    } else if let data = try? await selectedItem?.loadTransferable(
                                        type: Data.self)
                                    {
                                        selectedImage = PlatformImage(data: data)
                                    }
                                }
                            }
                        #else
                            Button("Select Image/Video") {
                                showingImagePicker = true
                            }
                            .fileImporter(
                                isPresented: $showingImagePicker,
                                allowedContentTypes: [.image, .movie]
                            ) { result in
                                switch result {
                                case .success(let file):
                                    Task { @MainActor in
                                        do {
                                            let data = try loadData(from: file)
                                            if let image = PlatformImage(data: data) {
                                                selectedImage = image
                                            } else if let fileType = UTType(
                                                filenameExtension: file.pathExtension),
                                                fileType.conforms(to: .movie)
                                            {
                                                if let sandboxURL = try? loadVideoToSandbox(
                                                    from: file)
                                                {
                                                    selectedVideoURL = sandboxURL
                                                }
                                            } else {
                                                print("Failed to create image from data")
                                            }
                                        } catch {
                                            print(
                                                "Failed to load image: \(error.localizedDescription)"
                                            )
                                        }
                                    }
                                case .failure(let error):
                                    print(error.localizedDescription)
                                }
                            }
                        #endif

                        if selectedImage != nil {
                            Button("Clear", role: .destructive) {
                                selectedImage = nil
                                selectedItem = nil
                            }
                        }
                    }
                }
                .padding()

                HStack {
                    Spacer()
                    if llm.running {
                        ProgressView()
                            .frame(maxHeight: 20)
                        Spacer()
                    }
                }
            }

            ScrollView(.vertical) {
                ScrollViewReader { sp in
                    Text(llm.output)
                        .textSelection(.enabled)
                        .onChange(of: llm.output) { _, _ in
                            sp.scrollTo("bottom")
                        }

                    Spacer()
                        .frame(width: 1, height: 1)
                        .id("bottom")
                }
            }
            .frame(minHeight: 200)

            HStack {
                TextField("prompt", text: Bindable(llm).prompt)
                    .onSubmit(generate)
                    .disabled(llm.running)
                    #if os(visionOS)
                        .textFieldStyle(.roundedBorder)
                    #endif
                Button(llm.running ? "stop" : "generate", action: llm.running ? cancel : generate)
            }
        }
        .onAppear {
            selectedVideoURL = URL(
                string:
                    "https://videos.pexels.com/video-files/4066325/4066325-uhd_2560_1440_24fps.mp4")!
        }
        #if os(visionOS)
            .padding(40)
        #else
            .padding()
        #endif
        .toolbar {
            ToolbarItem {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Memory")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    Text(deviceStat.gpuUsage.activeMemory.formatted(.byteCount(style: .memory)))
                        .font(.caption2)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .help(
                    Text(
                        """
                        Active: \(deviceStat.gpuUsage.activeMemory.formatted(.byteCount(style: .memory)))/\(GPU.memoryLimit.formatted(.byteCount(style: .memory)))
                        Cache: \(deviceStat.gpuUsage.cacheMemory.formatted(.byteCount(style: .memory)))/\(GPU.cacheLimit.formatted(.byteCount(style: .memory)))
                        Peak: \(deviceStat.gpuUsage.peakMemory.formatted(.byteCount(style: .memory)))
                        """
                    )
                )
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        copyToClipboard(llm.output)
                    }
                } label: {
                    Label("Copy Output", systemImage: "doc.on.doc.fill")
                }
                .disabled(llm.output == "")
                .labelStyle(.titleAndIcon)
            }
        }
        .task {
            _ = try? await llm.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            // Handle memory warning on iOS - emergency response
            llm.emergencyMemoryReset()
        }
    }

    private func generate() {
        Task {
            if let selectedImage = selectedImage {
                #if os(iOS) || os(visionOS)
                    // Convert UIImage to CIImage with validation
                    guard let ciImage = createValidCIImage(from: selectedImage) else {
                        await MainActor.run {
                            self.llm.output = "图像格式无效，请尝试其他图片"
                        }
                        return
                    }
                    llm.generate(image: ciImage, videoURL: nil)
                #else
                    if let cgImage = selectedImage.cgImage(
                        forProposedRect: nil, context: nil, hints: nil)
                    {
                        let ciImage = CIImage(cgImage: cgImage)
                        llm.generate(image: ciImage, videoURL: nil)
                    }
                #endif
            } else if let imageURL = currentImageURL {
                do {
                    let (data, _) = try await URLSession.shared.data(from: imageURL)
                    if let ciImage = createValidCIImage(from: data) {
                        llm.generate(image: ciImage, videoURL: nil)
                    } else {
                        await MainActor.run {
                            self.llm.output = "下载的图像格式无效"
                        }
                    }
                } catch {
                    print("Failed to load image: \(error.localizedDescription)")
                    await MainActor.run {
                        self.llm.output = "图像加载失败: \(error.localizedDescription)"
                    }
                }
            } else {
                if let videoURL = selectedVideoURL {
                    llm.generate(image: nil, videoURL: videoURL)
                }
            }
        }
    }

    #if os(iOS) || os(visionOS)
    private func createValidCIImage(from image: UIImage) -> CIImage? {
        // Always convert to ensure valid format
        return convertToValidFormat(image: image)
    }

    private func convertToValidFormat(image: UIImage) -> CIImage? {
        // Force convert to standard RGBA8 format to avoid MLX validation errors
        let size = image.size
        let rect = CGRect(origin: .zero, size: size)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Ensure 1x scale to avoid validation issues
        format.opaque = false
        format.preferredRange = .standard // Use standard range

        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let convertedImage = renderer.image { ctx in
            // Set standard color space
            ctx.cgContext.setFillColor(UIColor.clear.cgColor)
            ctx.cgContext.fill(rect)

            // Draw image in standard format
            image.draw(in: rect)
        }

        guard let finalCGImage = convertedImage.cgImage else { return nil }

        // Final validation
        let bitsPerComponent = finalCGImage.bitsPerComponent
        let bitsPerPixel = finalCGImage.bitsPerPixel
        let bytesPerRow = finalCGImage.bytesPerRow

        print("Image format: \(bitsPerComponent)bpc, \(bitsPerPixel)bpp, \(bytesPerRow)bpr")

        // Ensure we have valid parameters
        guard bitsPerComponent == 8 && (bitsPerPixel == 32 || bitsPerPixel == 24) else {
            print("Warning: Image format still invalid after conversion, proceeding anyway")
            // Continue anyway as the conversion should have handled most issues
            return CIImage(cgImage: finalCGImage)
        }

        return CIImage(cgImage: finalCGImage)
    }
    #endif

    private func createValidCIImage(from data: Data) -> CIImage? {
        guard let ciImage = CIImage(data: data) else { return nil }

        // Convert to UIImage to ensure proper format validation
        #if os(iOS) || os(visionOS)
        if let uiImage = UIImage(data: data) {
            return createValidCIImage(from: uiImage)
        }
        #endif

        // Fallback for other platforms or if UIImage conversion fails
        return ciImage
    }

    private func cancel() {
        llm.cancelGeneration()
    }

    #if os(macOS)
        private func loadData(from url: URL) throws -> Data {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(
                    domain: "FileAccess", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to access the file."])
            }
            defer { url.stopAccessingSecurityScopedResource() }
            return try Data(contentsOf: url)
        }

        private func loadVideoToSandbox(from url: URL) throws -> URL {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(
                    domain: "FileAccess", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to access the file."])
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let sandboxURL = try SandboxFileTransfer.transferFileToTemp(from: url)
            return sandboxURL
        }
    #endif

    private func copyToClipboard(_ string: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #else
            UIPasteboard.general.string = string
        #endif
    }
}

@Observable
@MainActor
class VLMEvaluator {

    var running = false

    var prompt = ""
    var output = ""
    var modelInfo = ""
    var stat = ""

    /// This controls which model loads. `smolvlm` is very small even unquantized, so it will fit on
    /// more devices.
    let modelConfiguration = VLMRegistry.smolvlm

    /// parameters controlling the output – use values appropriate for the model selected above
    var generateParameters: MLXLMCommon.GenerateParameters {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let isUltraLowMemoryDevice = physicalMemory <= 3 * 1024 * 1024 * 1024 // 3GB
        let isLowMemoryDevice = physicalMemory <= 4 * 1024 * 1024 * 1024 // 4GB

        if isUltraLowMemoryDevice {
            // Emergency minimal parameters for critical memory situations
            return MLXLMCommon.GenerateParameters(
                maxTokens: 50, temperature: 0.7, topP: 0.9)
        } else if isLowMemoryDevice {
            // Reduced parameters for low-memory devices
            return MLXLMCommon.GenerateParameters(
                maxTokens: 300, temperature: 0.7, topP: 0.9)
        } else {
            // Standard parameters for other devices
            return MLXLMCommon.GenerateParameters(
                maxTokens: 600, temperature: 0.7, topP: 0.9)
        }
    }
    let updateInterval = Duration.seconds(0.25)

    /// A task responsible for handling the generation process.
    var generationTask: Task<Void, Error>?

    enum LoadState {
        case idle
        case loaded(ModelContainer)
    }

    var loadState = LoadState.idle

    /// Helper to check if device has low memory
    private var isLowMemoryDevice: Bool {
        ProcessInfo.processInfo.physicalMemory <= 4 * 1024 * 1024 * 1024 // 4GB
    }

    /// Ultra low memory device (iPhone 13 mini class)
    private var isUltraLowMemoryDevice: Bool {
        ProcessInfo.processInfo.physicalMemory <= 3 * 1024 * 1024 * 1024 // 3GB
    }

    /// load and return the model -- can be called multiple times, subsequent calls will
    /// just return the loaded model
    func load() async throws -> ModelContainer {
        switch loadState {
        case .idle:
            if isUltraLowMemoryDevice {
                // Emergency limits for critical memory situations
                MLX.GPU.set(cacheLimit: 1 * 1024 * 1024) // 1MB cache
                MLX.GPU.set(memoryLimit: 1_200 * 1024 * 1024) // 1.2GB limit
            } else if isLowMemoryDevice {
                // Aggressive memory limits for low-memory devices
                MLX.GPU.set(cacheLimit: 3 * 1024 * 1024) // 3MB cache
                MLX.GPU.set(memoryLimit: 1_800 * 1024 * 1024) // 1.8GB limit
            } else {
                // Conservative limits for other devices
                MLX.GPU.set(cacheLimit: 10 * 1024 * 1024) // 10MB cache
            }

            let modelContainer = try await VLMModelFactory.shared.loadContainer(
                configuration: modelConfiguration
            ) { [modelConfiguration] progress in
                Task { @MainActor in
                    self.modelInfo =
                        "Downloading \(modelConfiguration.name): \(Int(progress.fractionCompleted * 100))%"
                }
            }

            let numParams = await modelContainer.perform { context in
                context.model.numParameters()
            }

            self.prompt = modelConfiguration.defaultPrompt

            let modelName = "SmolVLM" // Simplified name for display
            let weightsMB = numParams / (1024*1024)

            if isUltraLowMemoryDevice {
                // For ultra low-memory devices, don't cache the model to prevent memory buildup
                self.modelInfo = "\(modelName) • \(weightsMB)M • Ultra Low Memory"
                return modelContainer
            } else if isLowMemoryDevice {
                // For low-memory devices, don't cache the model to prevent memory buildup
                self.modelInfo = "\(modelName) • \(weightsMB)M • Low Memory"
                return modelContainer
            } else {
                self.modelInfo = "\(modelName) • \(weightsMB)M"
                loadState = .loaded(modelContainer)
                return modelContainer
            }

        case .loaded(let modelContainer):
            return modelContainer
        }
    }

    private func generate(prompt: String, image: CIImage?, videoURL: URL?) async {

        self.output = ""

        do {
            let modelContainer = try await load()

            // each time you generate you will get something new
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

            // Aggressive memory cleanup before generation
            if isLowMemoryDevice || isUltraLowMemoryDevice {
                GPU.clearCache()
                eval() // Force immediate evaluation

                // Additional emergency cleanup for ultra low memory
                if isUltraLowMemoryDevice {
                    // Force garbage collection multiple times
                    for _ in 0..<3 {
                        autoreleasepool {
                            eval()
                            GPU.clearCache()
                        }
                    }
                }
            }

            try await modelContainer.perform { (context: ModelContext) -> Void in
                let images: [UserInput.Image] = if let image { [.ciImage(image)] } else { [] }
                let videos: [UserInput.Video] = if let videoURL { [.url(videoURL)] } else { [] }

                let systemPrompt =
                    if !videos.isEmpty {
                        videoSystemPrompt
                    } else if !images.isEmpty {
                        imageSystemPrompt
                    } else { "You are a helpful assistant." }

                let chat: [Chat.Message] = [
                    .system(systemPrompt),
                    .user(prompt, images: images, videos: videos),
                ]

                let physicalMemory = ProcessInfo.processInfo.physicalMemory
                let isUltraLowMemoryDevice = physicalMemory <= 3 * 1024 * 1024 * 1024 // 3GB
                let isLowMemoryDevice = physicalMemory <= 4 * 1024 * 1024 * 1024 // 4GB

                var generateParams: MLXLMCommon.GenerateParameters
                if isUltraLowMemoryDevice {
                    generateParams = MLXLMCommon.GenerateParameters(
                        maxTokens: 200, temperature: 0.7, topP: 0.9)
                } else if isLowMemoryDevice {
                    generateParams = MLXLMCommon.GenerateParameters(
                        maxTokens: 400, temperature: 0.7, topP: 0.9)
                } else {
                    generateParams = MLXLMCommon.GenerateParameters(
                        maxTokens: 800, temperature: 0.7, topP: 0.9)
                }

                var userInput = UserInput(chat: chat)

                // Aggressive image size reduction for memory constraints
                if isUltraLowMemoryDevice {
                    userInput.processing.resize = .init(width: 160, height: 160) // Ultra small for critical memory
                } else if isLowMemoryDevice {
                    userInput.processing.resize = .init(width: 224, height: 224) // Small for low memory
                } else {
                    userInput.processing.resize = .init(width: 448, height: 448) // Standard size
                }

                let lmInput = try await context.processor.prepare(input: userInput)

                let stream = try MLXLMCommon.generate(
                    input: lmInput, parameters: generateParams, context: context)

                // generate and output in batches
                for await batch in stream._throttle(
                    for: updateInterval, reducing: Generation.collect)
                {
                    let output = batch.compactMap { $0.chunk }.joined(separator: "")
                    if !output.isEmpty {
                        Task { @MainActor [output] in
                            self.output += output
                        }
                    }

                    if let completion = batch.compactMap({ $0.info }).first {
                        Task { @MainActor in
                            let speed = String(format: "%.1f", completion.tokensPerSecond)
                            self.stat = "\(speed) t/s"
                        }
                    }
                }
            }

            // Emergency cleanup: immediately unload model after generation
            if isUltraLowMemoryDevice {
                unloadModel()
            }

        } catch {
            output = "Failed: \(error)"
        }
    }

    func generate(image: CIImage?, videoURL: URL?) {
        guard !running else { return }
        let currentPrompt = prompt
        prompt = ""
        generationTask = Task {
            running = true
            await generate(prompt: currentPrompt, image: image, videoURL: videoURL)
            running = false
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        running = false

        // Clear memory after cancellation on low-memory devices
        if isLowMemoryDevice || isUltraLowMemoryDevice {
            GPU.clearCache()

            // Additional cleanup for ultra low memory devices
            if isUltraLowMemoryDevice {
                unloadModel()
            }
        }
    }

    /// Clear model from memory to free up space (called on low-memory devices)
    func unloadModel() {
        if case .loaded = loadState {
            loadState = .idle
            GPU.clearCache()

            // Force garbage collection on ultra low memory devices
            if isUltraLowMemoryDevice {
                // Maximum cleanup effort
                for _ in 0..<5 {
                    autoreleasepool {
                        eval()
                        GPU.clearCache()
                        // Small delay to allow cleanup
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                }
            }
        }
    }

    /// Emergency memory reset function
    func emergencyMemoryReset() {
        unloadModel()
        GPU.clearCache()
        eval()

        // Additional emergency cleanup
        if isUltraLowMemoryDevice {
            for _ in 0..<3 {
                autoreleasepool {
                    eval()
                    GPU.clearCache()
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }
    }
}

#if os(iOS) || os(visionOS)
    struct TransferableVideo: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { movie in
                SentTransferredFile(movie.url)
            } importing: { received in
                let sandboxURL = try SandboxFileTransfer.transferFileToTemp(from: received.file)
                return .init(url: sandboxURL)
            }
        }
    }
#endif

struct SandboxFileTransfer {
    static func transferFileToTemp(from sourceURL: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let sandboxURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)

        if FileManager.default.fileExists(atPath: sandboxURL.path()) {
            try FileManager.default.removeItem(at: sandboxURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: sandboxURL)
        return sandboxURL
    }
}
