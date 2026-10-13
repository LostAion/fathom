import Foundation
import Testing
@testable import Fathom

struct WireFormatTests {
    @Test func decimalStringsParseExactly() {
        #expect(Decimal(apiString: "50000000.00") == Decimal(50_000_000))
        #expect(Decimal(apiString: "40.50") == Decimal(string: "40.5"))
        #expect(Decimal(apiString: nil) == nil)
        #expect(Decimal(apiString: "abc") == nil)
    }

    @Test func decimalRoundTripsToString() {
        #expect(Decimal(string: "12500.75")!.apiString == "12500.75")
    }

    @Test func policyDecodesFromServerJSON() throws {
        let json = """
        {"issue_date":"2026-01-01","expiry_date":"2026-12-31","premium":"45000.00",
         "sum_insured":"50000000.00","policy_type":"HULL","vessel_value_covered":"50000000.00",
         "cargo_type":null,"liability_limit":null,"status":"BOUND","deductible":"10000.00",
         "client_id":1,"broker_id":1,"emp_id":1,"vessel_id":1,"cargo_id":null,"policy_no":1}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let policy = try decoder.decode(Policy.self, from: Data(json.utf8))

        #expect(policy.id == 1)
        #expect(policy.policyType == .hull)
        #expect(policy.lifecycle == .bound)
        #expect(policy.premiumAmount == Decimal(45_000))
        #expect(policy.expires == APIDate.parse("2026-12-31"))
    }

    @Test func junctionPathsUseBothKeys() {
        #expect(ReinsuredBy(policyNo: 3, reinsurerId: 2).resourcePath == "reinsured-by/3/2")
        #expect(Vessel(vesselId: 7, name: "x", imoNumber: "1").resourcePath == "vessels/7")
    }
}
