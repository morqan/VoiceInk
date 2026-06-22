# Contributing to VoiceInk

This is a personal fork of VoiceInk, maintained primarily for my own use. It is shared openly
under the GPL-v3 license so others can read, build, and learn from it.

## How you can use and contribute

- 🍴 **Fork it** — you're welcome to fork this repository and adapt it for your own needs.
- 🐛 **Report bugs** — open an issue with steps to reproduce and details about your environment.
- 💡 **Suggest ideas** — open an issue describing the feature and why it would help.
- 📖 **Improve docs** — corrections and clarifications to the documentation are welcome.

Pull requests are considered case by case; for anything non-trivial, please open an issue to
discuss it first.

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Development Setup

1. Requirements:
   - macOS 14.4 or later
   - Latest version of Xcode
   - Latest version of Swift
   - whisper.cpp / `whisper.xcframework` set up (see [BUILDING.md](BUILDING.md))

2. Build and run:
   - Follow [BUILDING.md](BUILDING.md). `make dev` builds and runs; `make local` builds a
     self-signed local app with no Apple Developer account.

3. Before submitting changes:
   - Run the test suite (`xcodebuild test -scheme VoiceInk -destination 'platform=macOS'`)
   - Make sure existing tests pass and add tests for new behavior where it makes sense

## Style Guidelines

- Follow standard Swift style
- Use meaningful variable and function names
- Keep functions focused and concise; one primary type per file, named after it
- Keep view files focused — split a screen into sections/subviews rather than growing one large `body`
- Comment non-obvious logic; prefer self-documenting code

## Architecture

For a map of the codebase and the critical dictation path, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Questions?

Open an issue or start a discussion. Thanks for your interest in VoiceInk! 🎉
