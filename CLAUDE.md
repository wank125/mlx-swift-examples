# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the MLX Swift Examples repository containing example Swift programs for MLX, Apple's machine learning framework. The repo includes:

- **Libraries**: Core Swift packages for different ML model types (LLM, VLM, MNIST, Embedders, Stable Diffusion)
- **Applications**: iOS/macOS apps demonstrating MLX capabilities (MNISTTrainer, LLMEval, VLMEval, MLXChatExample, StableDiffusionExample)
- **Tools**: Command-line utilities for various ML tasks
- **Tests**: Unit tests for the library components

## Running and Building

### Command Line Tools
Use the `mlx-run` script to execute command-line tools:

```bash
# Run with default release configuration
./mlx-run llm-tool --prompt "your prompt here"

# Run with debug configuration
./mlx-run --debug llm-tool --help

# List all available tools/schemes
./mlx-run --list
```

Available tools include:
- `llm-tool`: Generate text using various LLMs
- `ExampleLLM`: Simplified API for LLM interaction
- `mnist-tool`: Train a LeNet model on MNIST data
- `LinearModelTraining`: Train simple linear models
- `image-tool`: Generate images using stable diffusion models

### Building in Xcode
All components can be built and run directly from Xcode. The project uses the standard Xcode build system with Swift Package Manager integration. The main Xcode project is `mlx-swift-examples.xcodeproj`.

### Testing
Run tests using standard Swift Package Manager commands:
```bash
# Run all tests
swift test

# Run specific test suites
swift test --filter MLXLMTests
swift test --filter MLXVLMTests
```

## Architecture

### Core Libraries
- **MLXLMCommon**: Shared API and utilities for LLM/VLM operations including `ChatSession`, `ModelContainer`, and configuration management
- **MLXLLM**: Large language model implementations (Llama, Qwen, Mistral, etc.)
- **MLXVLM**: Vision language model implementations with image/video processing capabilities
- **MLXEmbedders**: Text embedding models (BERT, Sentence Transformers)
- **MLXMNIST**: MNIST digit recognition models and training utilities
- **StableDiffusion**: Image generation models (SDXL Turbo, Stable Diffusion)

### Model Loading and Management
The libraries use a unified model loading system through `loadModel(id:)` that:
- Downloads models from Hugging Face hub automatically
- Handles quantized models (4-bit, 8-bit) for efficient inference
- Supports model configuration files for tokenizer and model parameters
- Manages model lifecycle with automatic memory management

### Key Dependencies
- MLX Swift (main ML framework with tensor operations)
- Swift Transformers (Hugging Face model integration and tokenization)
- GzipSwift (for MNIST data compression)
- Swift Argument Parser (for command-line tools)

### Simplified API Usage
The libraries provide a streamlined API for model interaction:

```swift
// LLM interaction
let model = try await loadModel(id: "mlx-community/Qwen3-4B-4bit")
let session = ChatSession(model)
print(try await session.respond(to: "Your question here"))

// VLM interaction
let vlm = try await loadVLM(id: "mlx-community/llava-v1.5-7b")
let result = try await vlm.describe(image: image, prompt: "What do you see?")
```

## Development Environment

- **Minimum Swift version**: 5.9
- **Platform support**: macOS 14+, iOS 16+, visionOS 1+
- **Xcode**: Latest version recommended
- **Build configurations**: Debug/Release (controlled via mlx-run script)
- **Swift concurrency**: Strict concurrency enabled for all library targets

## Project Structure

- `Package.swift`: Root package defining all libraries and dependencies
- `Libraries/`: Core Swift packages organized by functionality
- `Applications/`: iOS/macOS/visionOS example apps
- `Tools/`: Command-line utilities
- `Tests/`: Unit tests for library components
- `mlx-run`: Helper script for running command-line tools
- `Configuration/Build.xcconfig`: Xcode build configuration
- `mlx-swift-examples.xcodeproj`: Main Xcode project file

## Application Architecture

### Key Applications
- **VLMEval**: Vision-language model evaluation app with prompt templates and multi-image support
- **LLMEval**: Text-based LLM evaluation app
- **MLXChatExample**: Multi-model chat interface supporting both LLMs and VLMs
- **MNISTTrainer**: Interactive MNIST training and visualization
- **StableDiffusionExample**: Text-to-image generation with various SD models

### Common UI Patterns
- SwiftUI-based with async/await for model inference
- Cross-platform support using `PlatformImage` type alias
- Progress indicators for model loading and inference
- Error handling with retry mechanisms
- Device stat monitoring and performance optimization

## Integration for External Projects

Add this repository as a Swift Package dependency:
```swift
.package(url: "https://github.com/ml-explore/mlx-swift-examples/", branch: "main")
```

Then import specific libraries like:
```swift
.product(name: "MLXLLM", package: "mlx-swift-examples")
```