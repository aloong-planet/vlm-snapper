import Sparkle
import Testing

@Suite("Single-version Sparkle policy")
struct SparkleVersionPolicyTests {
    @Test("Three-part updates use numeric component ordering")
    func increasingVersionIsNewer() {
        let comparator = SUStandardVersionComparator.default
        #expect(comparator.compareVersion("0.1.1", toVersion: "0.1.0") == .orderedDescending)
        #expect(comparator.compareVersion("0.10.0", toVersion: "0.9.9") == .orderedDescending)
        #expect(comparator.compareVersion("1.0.0", toVersion: "0.99.99") == .orderedDescending)
    }

    @Test("Rebuilding the same version is not a new update")
    func sameVersionIsEqual() {
        #expect(SUStandardVersionComparator.default.compareVersion(
            "0.1.1", toVersion: "0.1.1"
        ) == .orderedSame)
    }

    @Test("Legacy integer builds require explicit migration")
    func integerBuildDoesNotAutomaticallyMigrate() {
        #expect(SUStandardVersionComparator.default.compareVersion(
            "0.1.1", toVersion: "51"
        ) == .orderedAscending)
    }
}
