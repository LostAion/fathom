import Foundation

// Mirrors app/schemas.py. JSON keys are snake_case; the API client converts them.
// Money and percentages arrive as decimal strings ("45000.00"), dates as "yyyy-MM-dd".
// On create, the server ignores the primary key we send, so new rows use id 0.

nonisolated protocol APIModel: Codable, Identifiable, Hashable {
    static var collection: String { get }
    var resourcePath: String { get }
}

nonisolated extension APIModel where ID == Int {
    var resourcePath: String { "\(Self.collection)\(id)" }
}

// MARK: - Enums

nonisolated enum PolicyType: String, Codable, CaseIterable, Identifiable {
    case hull = "HULL"
    case cargo = "CARGO"
    case pi = "PI"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hull: "Hull & Machinery"
        case .cargo: "Cargo Transit"
        case .pi: "Protection & Indemnity"
        }
    }
}

nonisolated enum PolicyStatus: String, CaseIterable {
    case draft = "DRAFT"
    case quoted = "QUOTED"
    case bound = "BOUND"
    case active = "ACTIVE"
    case cancelled = "CANCELLED"
}

nonisolated enum ClaimStatus: String, CaseIterable {
    case reported = "REPORTED"
    case underSurvey = "UNDER_SURVEY"
    case settled = "SETTLED"
    case rejected = "REJECTED"
}

// MARK: - Independent entities

nonisolated struct Client: APIModel {
    static let collection = "clients/"
    var clientId: Int
    var name: String
    var address: String?
    var id: Int { clientId }
}

nonisolated struct Broker: APIModel {
    static let collection = "brokers/"
    var brokerId: Int
    var agencyName: String
    var licenceNo: String
    var id: Int { brokerId }
}

nonisolated struct Surveyor: APIModel {
    static let collection = "surveyors/"
    var surveyorId: Int
    var name: String
    var qualification: String?
    var id: Int { surveyorId }
}

nonisolated struct Reinsurer: APIModel {
    static let collection = "reinsurers/"
    var reinsurerId: Int
    var name: String
    var id: Int { reinsurerId }
}

nonisolated struct Cargo: APIModel {
    static let collection = "cargos/"
    var cargoId: Int
    var description: String?
    var value: String?
    var id: Int { cargoId }
    var valueAmount: Decimal? { Decimal(apiString: value) }
}

nonisolated struct Vessel: APIModel {
    static let collection = "vessels/"
    var vesselId: Int
    var name: String
    var imoNumber: String
    var tonnage: Int?
    var flag: String?
    var id: Int { vesselId }
}

nonisolated struct Department: APIModel {
    static let collection = "departments/"
    var deptId: Int
    var name: String
    var location: String?
    var id: Int { deptId }
}

// MARK: - Dependent entities

nonisolated struct Underwriter: APIModel {
    static let collection = "underwriters/"
    var empId: Int
    var name: String
    var designation: String?
    var deptId: Int?
    var id: Int { empId }
}

nonisolated struct Voyage: APIModel {
    static let collection = "voyages/"
    var voyageId: Int
    var originPort: String?
    var destPort: String?
    var departDate: String?
    var vesselId: Int?
    var id: Int { voyageId }
    var departs: Date? { APIDate.parse(departDate) }
}

nonisolated struct Policy: APIModel {
    static let collection = "policies/"
    var policyNo: Int
    var issueDate: String?
    var expiryDate: String?
    var premium: String?
    var sumInsured: String?
    var policyType: PolicyType?
    var vesselValueCovered: String?
    var cargoType: String?
    var liabilityLimit: String?
    var status: String?
    var deductible: String?
    var clientId: Int?
    var brokerId: Int?
    var empId: Int?
    var vesselId: Int?
    var cargoId: Int?
    var id: Int { policyNo }

    var premiumAmount: Decimal? { Decimal(apiString: premium) }
    var sumInsuredAmount: Decimal? { Decimal(apiString: sumInsured) }
    var deductibleAmount: Decimal? { Decimal(apiString: deductible) }
    var issued: Date? { APIDate.parse(issueDate) }
    var expires: Date? { APIDate.parse(expiryDate) }
    var lifecycle: PolicyStatus? { status.flatMap(PolicyStatus.init(rawValue:)) }
}

nonisolated struct Claim: APIModel {
    static let collection = "claims/"
    var claimId: Int
    var lossDate: String?
    var claimAmount: String?
    var policyNo: Int?
    var status: String?
    var deductibleApplied: String?
    var settledAmount: String?
    var id: Int { claimId }

    var claimAmountValue: Decimal? { Decimal(apiString: claimAmount) }
    var settledAmountValue: Decimal? { Decimal(apiString: settledAmount) }
    var lost: Date? { APIDate.parse(lossDate) }
    var state: ClaimStatus? { status.flatMap(ClaimStatus.init(rawValue:)) }
}

// MARK: - Junctions (composite keys)

nonisolated struct ReinsuredBy: APIModel {
    static let collection = "reinsured-by/"
    var policyNo: Int
    var reinsurerId: Int
    var sharePercent: String?
    var id: String { "\(policyNo)_\(reinsurerId)" }
    var resourcePath: String { "\(Self.collection)\(policyNo)/\(reinsurerId)" }
    var share: Decimal? { Decimal(apiString: sharePercent) }
}

nonisolated struct AssessedBy: APIModel {
    static let collection = "assessed-by/"
    var claimId: Int
    var surveyorId: Int
    var id: String { "\(claimId)_\(surveyorId)" }
    var resourcePath: String { "\(Self.collection)\(claimId)/\(surveyorId)" }
}

nonisolated struct Carries: APIModel {
    static let collection = "carries/"
    var voyageId: Int
    var cargoId: Int
    var id: String { "\(voyageId)_\(cargoId)" }
    var resourcePath: String { "\(Self.collection)\(voyageId)/\(cargoId)" }
}

// MARK: - Other responses

nonisolated struct Health: Decodable {
    var status: String
    var database: String
}

// MARK: - Wire format helpers

nonisolated extension Decimal {
    init?(apiString: String?) {
        guard let apiString, let value = Decimal(string: apiString, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        self = value
    }

    var apiString: String { NSDecimalNumber(decimal: self).stringValue }
}

nonisolated enum APIDate {
    private static let style = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day().dateSeparator(.dash)

    static func parse(_ string: String?) -> Date? { string.flatMap { try? Date($0, strategy: style) } }
    static func string(_ date: Date) -> String { date.formatted(style) }
}
