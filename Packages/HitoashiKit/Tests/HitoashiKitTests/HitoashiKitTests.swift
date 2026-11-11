@testable import HitoashiKit
import Testing

struct HitoashiKitTests {
    @Test func rulesVersionIsPositive() {
        #expect(HitoashiKit.rulesVersion > 0)
    }
}
