import Testing
@testable import ThingsBarCore

@Test func versionIsSet() {
    #expect(!ThingsBarInfo.version.isEmpty)
}
