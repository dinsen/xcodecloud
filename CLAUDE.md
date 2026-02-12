# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**xcodecloud** is a multi-platform (iOS + macOS) SwiftUI app for monitoring and managing Apple Xcode Cloud CI/CD builds. It connects to the App Store Connect API to display build status, trigger builds, and manage workflows. An optional PHP webhook backend enables iOS Live Activity support for real-time build tracking in Dynamic Island.

No external package dependencies — pure Apple frameworks only (SwiftUI, Observation, CryptoKit, Security, ActivityKit, WidgetKit).

## Build & Test Commands

Build and test using the `xcodebuildmcp-cli` skill or Xcode directly. The project has four targets:

- **xcodecloud** — main app (iOS & macOS)
- **xcodecloudLiveActivityWidget** — iOS Live Activity widget extension
- **xcodecloudTests** — unit tests (Swift Testing framework, not XCTest)
- **xcodecloudUITests** — UI tests

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) with mocks defined inline in test files. When writing new tests, follow this pattern — not XCTest.

## Architecture

### State Management

Single `BuildFeedStore` (`@Observable`, `@MainActor`) owns all app state and is injected via SwiftUI `@Environment`. It orchestrates API calls, auto-refresh scheduling, live status polling, and persists selected app/monitoring mode to `UserDefaults`. Views access it with `@Environment(BuildFeedStore.self)`.

User preferences (auto-refresh interval, live status config) are stored via `@AppStorage` in `ContentView` and passed into `BuildFeedStore` methods.

### Networking Layer

- `AppStoreConnectAPI` protocol defines all ASC API operations — implemented by `AppStoreConnectClient` (an `actor` for thread safety)
- `ASCRequestBuilder` is a static factory that constructs `URLRequest` objects with proper JSON:API headers, paths, and query parameters
- `JWTTokenFactory` generates ES256 JWT tokens for ASC authentication using `CryptoKit`
- `CIRunningBuildStatusAPI` / `CIRunningBuildStatusClient` — separate actor-based client for polling the custom webhook status endpoint
- All API response types are `private nonisolated struct`s within `AppStoreConnectClient.swift` — they parse JSON:API's nested `data`/`included`/`relationships` structure

### Credentials

Stored in Keychain via `CredentialsStore` protocol / `KeychainCredentialsStore` implementation (service: `"ios.dinsen.xcodecloud"`). Changes broadcast via `NotificationCenter` (`.appStoreConnectCredentialsDidChange`).

### Multi-Platform

Conditional compilation (`#if os(macOS)` / `#if os(iOS)`) is used for:
- macOS: `MenuBarExtra` with build status symbol, `Settings` scene, `openSettings` environment action
- iOS: Live Activity via `ActivityKit`, settings shown as a sheet

### Feature Organization

Views live under `Features/` grouped by feature (Dashboard, BuildDetail, BuildTrigger, Settings, Workflows, Compatibility, Repositories, MenuBar, AppSelection). Each feature directory typically contains one view file.

### Widget Target

`xcodecloudLiveActivityWidget` uses `BuildLiveActivityAttributes` (shared with main app via `BuildLiveActivityManager`) to show running build counts in Dynamic Island and Lock Screen.

### PHP Backend

Optional webhook system at repo root (`webhook.php`, `status.php`, `config.php`, `schema.sql`). Receives Xcode Cloud webhook events, tracks running builds in MySQL, and exposes a status endpoint the app polls. Verifies HMAC-SHA256 signatures when `XCC_WEBHOOK_SECRET` is set.

## Testing Conventions

- Tests use protocol-based mocking: `MockCredentialsStore` and `MockAppStoreConnectAPI` are defined as `private final class` within test files
- `BuildFeedStore` is tested indirectly through `SettingsViewModel` tests
- Model tests verify `Codable` round-trips, status derivation logic, and display formatting
