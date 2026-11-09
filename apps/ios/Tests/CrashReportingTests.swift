#if !canImport(DrillbitCore)
  import Foundation
  import Sentry
  import Testing
  @testable import Drillbit

  struct CrashReportingTests {
    @Test func dropsThePerInstallHashAndKeepsTheRest() {
      let contexts = CrashReporting.withoutInstallHash([
        "app": ["device_app_hash": "f00d", "app_version": "1.0", "app_build": "21"],
        "device": ["model": "iPhone15,4"],
      ])
      #expect(contexts?["app"]?["device_app_hash"] == nil)
      #expect(contexts?["app"]?["app_build"] as? String == "21")
      #expect(contexts?["device"]?["model"] as? String == "iPhone15,4")
      #expect(CrashReporting.withoutInstallHash(nil) == nil)
    }

    @Test func serverErrorsCarryTheWorkersRequestId() {
      let url = URL(string: "https://api.drillbit.t23.dev/v1/challenges/0f8fad5b-d9cb-469f-a165-70867728950e/interview?draft=x")!
      let response = HTTPURLResponse(
        url: url, statusCode: 500, httpVersion: nil, headerFields: ["X-Request-ID": "6a0b5c1e-request"])
      #expect(CrashReporting.serverTags(response) == ["endpoint": "/v1/challenges/:id/interview", "request_id": "6a0b5c1e-request"])
      let bare = HTTPURLResponse(url: url, statusCode: 502, httpVersion: nil, headerFields: [:])
      #expect(CrashReporting.serverTags(bare) == ["endpoint": "/v1/challenges/:id/interview"])
    }

    private func hang(_ packages: [String?], mechanism: String = "mx_hang_diagnostic") -> Event {
      let event = Event(level: .error)
      let exception = Exception(value: "MXHangDiagnostic hangDuration:6.545 sec", type: "MXHangDiagnostic")
      exception.mechanism = Mechanism(type: mechanism)
      exception.stacktrace = SentryStacktrace(
        frames: packages.map { package in
          let frame = Frame()
          frame.package = package
          return frame
        }, registers: [:])
      event.exceptions = [exception]
      return event
    }

    @Test func aHangInSystemCodeIsAWarningAndOneThroughOurCodeStaysAnError() {
      // DRILLBIT-IOS: main, the run loop, Core Animation, then a synchronous Metal compile and kernel frames.
      let shaders = hang(["dyld", "Drillbit", "UIKitCore", "QuartzCore", "RenderBox", "Metal", "libsystem_kernel.dylib", nil])
      CrashReporting.quietSystemHang(shaders, app: "Drillbit")
      #expect(shaders.level == .warning)
      #expect(shaders.tags?["hang"] == "system")

      let ours = hang(["dyld", "Drillbit", "UIKitCore", "SwiftUI", "Drillbit", "SwiftUI"])
      CrashReporting.quietSystemHang(ours, app: "Drillbit")
      #expect(ours.level == .error)
      #expect(ours.tags == nil)

      let crash = hang(["dyld", "Drillbit", "UIKitCore"], mechanism: "mx_crash_diagnostic")
      CrashReporting.quietSystemHang(crash, app: "Drillbit")
      #expect(crash.level == .error)
    }
  }
#endif
