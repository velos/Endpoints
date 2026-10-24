# Runtime-only consumer

This package uses `.package(path: "../..", traits: [])`. On SwiftPM 6.2 and later,
trait-disabled generator dependencies should not be fetched. CI asserts there are
no OpenAPIKit or Yams directories in this consumer's `.build/checkouts` on macOS.
SwiftPM 6.1 may fetch them despite the disabled trait; the Linux job does not make
the no-fetch assertion. Local Swift 6.4 observations are recorded in
../../docs/OpenAPIGenerator-Verification.md.
