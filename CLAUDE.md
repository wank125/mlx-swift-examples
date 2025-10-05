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

### Building in Xcode
All components can be built and run directly from Xcode. The project uses the standard Xcode build system with Swift Package Manager integration.

### Testing
Run tests using standard Swift Package Manager commands:
```bash
swift test --filter MLXLMTests
```

## Architecture

### Core Libraries
- **MLXLMCommon**: Shared API and utilities for LLM/VLM operations
- **MLXLLM**: Large language model implementations
- **MLXVLM**: Vision language model implementations
- **MLXEmbedders**: Text embedding models
- **MLXMNIST**: MNIST digit recognition models
- **StableDiffusion**: Image generation models

### Key Dependencies
- MLX Swift (main ML framework)
- Swift Transformers (Hugging Face integration)
- GzipSwift (for MNIST data compression)

### Simplified API Usage
The libraries provide a streamlined API for model interaction:

```swift
let model = try await loadModel(id: "mlx-community/Qwen3-4B-4bit")
let session = ChatSession(model)
print(try await session.respond(to: "Your question here"))
```

## Development Environment

- **Minimum Swift version**: 5.9
- **Platform support**: macOS 14+, iOS 16+
- **Xcode**: Latest version recommended
- **Build configurations**: Debug/Release (controlled via mlx-run script)

## Project Structure

- `Package.swift`: Root package defining all libraries and dependencies
- `Libraries/`: Core Swift packages organized by functionality
- `Applications/`: iOS/macOS example apps
- `Tools/`: Command-line utilities
- `Tests/`: Unit tests for library components
- `mlx-run`: Helper script for running command-line tools
- `Configuration/Build.xcconfig`: Xcode build configuration

## Integration for External Projects

Add this repository as a Swift Package dependency:
```swift
.package(url: "https://github.com/ml-explore/mlx-swift-examples/", branch: "main")
```

Then import specific libraries like:
```swift
.product(name: "MLXLLM", package: "mlx-swift-examples")
```