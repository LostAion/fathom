import Testing
@testable import Fathom

struct PortCatalogTests {
    @Test(arguments: ["Rotterdam", "Singapore", "Shanghai", "Los Angeles", "Yokohama", "Hamburg"])
    func seedVoyagePortsResolve(name: String) {
        #expect(PortCatalog.named(name) != nil)
    }

    @Test func lookupIgnoresCaseAndSpaces() {
        #expect(PortCatalog.named("  rotterdam ")?.locode == "NLRTM")
        #expect(PortCatalog.named("Atlantis") == nil)
        #expect(PortCatalog.named(nil) == nil)
    }

    @Test func locodesAreUnique() {
        #expect(Set(PortCatalog.all.map(\.locode)).count == PortCatalog.all.count)
    }

    @Test func flagComesFromCountryCode() {
        #expect(PortCatalog.named("Singapore")?.flag == "🇸🇬")
    }
}
