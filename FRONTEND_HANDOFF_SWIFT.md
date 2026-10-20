# Marine Insurance API — Swift / SwiftUI Frontend Handoff Guide

This document is the official integration guide for the iOS / macOS / iPadOS client application written in **Swift / SwiftUI**. It contains data contracts, network configurations, ready-to-copy `Codable` models, an async `actor APIClient`, and sample SwiftUI views.

---

## 1. 🌐 Connection & Network Configuration

### Base URLs
| Environment | Base URL | Notes |
|---|---|---|
| **iOS / macOS Simulator** | `http://127.0.0.1:8000/api` | Direct local loopback |
| **Physical iPhone / iPad** | `http://<YOUR_MAC_LAN_IP>:8000/api` | Both device & Mac must be on same Wi-Fi |
| **Interactive OpenAPI Docs**| `http://127.0.0.1:8000/docs` | Swagger UI with live schema testing |
| **API Health Check** | `http://127.0.0.1:8000/api/health` | Returns status and database name |

### ⚠️ Info.plist App Transport Security (ATS)
Because local development uses non-TLS HTTP (`http://`), you must allow local HTTP loads in your Xcode project's `Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

---

## 2. 📋 Data Serialization Rules in Swift

1. **Date Format**:
   - Dates are formatted as `yyyy-MM-dd` (e.g. `"2026-05-14"`).
   - Configure your `JSONDecoder` with:
     ```swift
     let dateFormatter = DateFormatter()
     dateFormatter.dateFormat = "yyyy-MM-dd"
     dateFormatter.locale = Locale(identifier: "en_US_POSIX")
     decoder.dateDecodingStrategy = .formatted(dateFormatter)
     ```
2. **Monetary & Decimal Fields**:
   - To preserve exact currency precision without floating-point inaccuracies, monetary amounts (e.g., `premium`, `sum_insured`, `claim_amount`, `value`, `share_percent`) are serialized as **Strings** in JSON (e.g., `"45000.00"`).
   - Swift models include a convenience computed property returning `Decimal` or `Double`.
3. **Primary Keys & Auto-Increment**:
   - All main entities have server-generated auto-increment IDs.
   - When creating (`POST`), do **not** supply the primary key.
   - Response payloads will return the created object including the new primary key.
4. **Error Responses**:
   - FastAPI returns HTTP status `400`, `404`, or `422` with a JSON payload:
     ```json
     { "detail": "Human-readable error description" }
     ```

---

## 3. 📦 Swift Codable Models

Create a file named `MarineInsuranceModels.swift` in your Xcode project:

```swift
import Foundation

// MARK: - Enums

public enum PolicyType: String, Codable, CaseIterable, Identifiable, Sendable {
    case hull = "HULL"
    case cargo = "CARGO"
    case pi = "PI"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .hull: return "Hull & Machinery"
        case .cargo: return "Cargo Transit"
        case .pi: return "Protection & Indemnity (P&I)"
        }
    }
}

// MARK: - Independent Entities

public struct Client: Codable, Identifiable, Sendable, Hashable {
    public let client_id: Int
    public var name: String
    public var address: String?

    public var id: Int { client_id }
}

public struct ClientCreate: Codable, Sendable {
    public var name: String
    public var address: String?
    
    public init(name: String, address: String? = nil) {
        self.name = name
        self.address = address
    }
}

public struct Broker: Codable, Identifiable, Sendable, Hashable {
    public let broker_id: Int
    public var agency_name: String
    public var licence_no: String

    public var id: Int { broker_id }
}

public struct Surveyor: Codable, Identifiable, Sendable, Hashable {
    public let surveyor_id: Int
    public var name: String
    public var qualification: String?

    public var id: Int { surveyor_id }
}

public struct Reinsurer: Codable, Identifiable, Sendable, Hashable {
    public let reinsurer_id: Int
    public var name: String

    public var id: Int { reinsurer_id }
}

public struct Cargo: Codable, Identifiable, Sendable, Hashable {
    public let cargo_id: Int
    public var description: String?
    public var value: String? // Decimal string

    public var id: Int { cargo_id }
    public var decimalValue: Decimal? { Decimal(string: value ?? "") }
}

public struct Vessel: Codable, Identifiable, Sendable, Hashable {
    public let vessel_id: Int
    public var name: String
    public var imo_number: String
    public var tonnage: Int?
    public var flag: String?

    public var id: Int { vessel_id }
}

public struct Department: Codable, Identifiable, Sendable, Hashable {
    public let dept_id: Int
    public var name: String
    public var location: String?

    public var id: Int { dept_id }
}

// MARK: - Dependent Entities

public struct Underwriter: Codable, Identifiable, Sendable, Hashable {
    public let emp_id: Int
    public var name: String
    public var designation: String?
    public var dept_id: Int?

    public var id: Int { emp_id }
}

public struct Voyage: Codable, Identifiable, Sendable, Hashable {
    public let voyage_id: Int
    public var origin_port: String?
    public var dest_port: String?
    public var depart_date: String? // "yyyy-MM-dd"
    public var vessel_id: Int?

    public var id: Int { voyage_id }
}

public struct Policy: Codable, Identifiable, Sendable, Hashable {
    public let policy_no: Int
    public var issue_date: String?       // "yyyy-MM-dd"
    public var expiry_date: String?      // "yyyy-MM-dd"
    public var premium: String?          // Decimal string e.g. "45000.00"
    public var sum_insured: String?      // Decimal string e.g. "50000000.00"
    public var policy_type: PolicyType?
    public var vessel_value_covered: String?
    public var cargo_type: String?
    public var liability_limit: String?
    public var client_id: Int?
    public var broker_id: Int?
    public var emp_id: Int?
    public var vessel_id: Int?
    public var cargo_id: Int?

    public var id: Int { policy_no }
    
    public var premiumAmount: Decimal? { Decimal(string: premium ?? "") }
    public var sumInsuredAmount: Decimal? { Decimal(string: sum_insured ?? "") }
}

public struct PolicyCreate: Codable, Sendable {
    public var issue_date: String?
    public var expiry_date: String?
    public var premium: String?
    public var sum_insured: String?
    public var policy_type: PolicyType?
    public var vessel_value_covered: String?
    public var cargo_type: String?
    public var liability_limit: String?
    public var client_id: Int?
    public var broker_id: Int?
    public var emp_id: Int?
    public var vessel_id: Int?
    public var cargo_id: Int?
    
    public init(
        policy_type: PolicyType,
        issue_date: String? = nil,
        expiry_date: String? = nil,
        premium: String? = nil,
        sum_insured: String? = nil,
        vessel_value_covered: String? = nil,
        client_id: Int? = nil,
        broker_id: Int? = nil,
        emp_id: Int? = nil,
        vessel_id: Int? = nil
    ) {
        self.policy_type = policy_type
        self.issue_date = issue_date
        self.expiry_date = expiry_date
        self.premium = premium
        self.sum_insured = sum_insured
        self.vessel_value_covered = vessel_value_covered
        self.client_id = client_id
        self.broker_id = broker_id
        self.emp_id = emp_id
        self.vessel_id = vessel_id
    }
}

public struct Claim: Codable, Identifiable, Sendable, Hashable {
    public let claim_id: Int
    public var loss_date: String?      // "yyyy-MM-dd"
    public var claim_amount: String?   // Decimal string e.g. "185000.00"
    public var policy_no: Int?

    public var id: Int { claim_id }
    public var claimAmountDecimal: Decimal? { Decimal(string: claim_amount ?? "") }
}

public struct ClaimCreate: Codable, Sendable {
    public var loss_date: String?
    public var claim_amount: String?
    public var policy_no: Int?
    
    public init(loss_date: String?, claim_amount: String?, policy_no: Int?) {
        self.loss_date = loss_date
        self.claim_amount = claim_amount
        self.policy_no = policy_no
    }
}

// MARK: - Junction Entities (Composite Keys)

public struct ReinsuredBy: Codable, Identifiable, Sendable, Hashable {
    public let policy_no: Int
    public let reinsurer_id: Int
    public var share_percent: String? // e.g. "40.00"

    public var id: String { "\(policy_no)_\(reinsurer_id)" }
    public var sharePercentDecimal: Decimal? { Decimal(string: share_percent ?? "") }
}

public struct AssessedBy: Codable, Identifiable, Sendable, Hashable {
    public let claim_id: Int
    public let surveyor_id: Int

    public var id: String { "\(claim_id)_\(surveyor_id)" }
}

public struct Carries: Codable, Identifiable, Sendable, Hashable {
    public let voyage_id: Int
    public let cargo_id: Int

    public var id: String { "\(voyage_id)_\(cargo_id)" }
}
```

---

## 4. 🚀 Swift Async/Await API Client

Create a file named `MarineInsuranceAPIClient.swift`:

```swift
import Foundation

public enum APIError: LocalizedError, Sendable {
    case invalidURL
    case serverError(statusCode: Int, message: String)
    case decodingError(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL is invalid."
        case .serverError(let code, let msg):
            return "Server Error (\(code)): \(msg)"
        case .decodingError(let msg):
            return "Failed to decode response: \(msg)"
        case .unknown(let msg):
            return msg
        }
    }
}

public actor MarineInsuranceAPIClient {
    public static let shared = MarineInsuranceAPIClient()
    
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    public init(baseURL: URL = URL(string: "http://127.0.0.1:8000/api")!) {
        self.baseURL = baseURL
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        
        self.encoder = JSONEncoder()
        
        self.decoder = JSONDecoder()
    }
    
    // MARK: - Core Generic Request Methods
    
    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown("Invalid response from server.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage: String
            if let errorObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorObj["detail"] as? String {
                errorMessage = detail
            } else {
                errorMessage = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            }
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
    
    private func executeNoContent(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown("Invalid response from server.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }

    // MARK: - Health Check
    
    public func checkHealth() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let request = URLRequest(url: url)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Policies API
    
    public func getPolicies(skip: Int = 0, limit: Int = 100, policyType: PolicyType? = nil) async throws -> [Policy] {
        var components = URLComponents(url: baseURL.appendingPathComponent("policies/"), resolvingAgainstBaseURL: true)!
        var queryItems = [
            URLQueryItem(name: "skip", value: "\(skip)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let type = policyType {
            queryItems.append(URLQueryItem(name: "policy_type", value: type.rawValue))
        }
        components.queryItems = queryItems
        
        let request = URLRequest(url: components.url!)
        return try await execute(request)
    }
    
    public func getPolicy(policyNo: Int) async throws -> Policy {
        let url = baseURL.appendingPathComponent("policies/\(policyNo)")
        return try await execute(URLRequest(url: url))
    }
    
    public func createPolicy(_ policy: PolicyCreate) async throws -> Policy {
        let url = baseURL.appendingPathComponent("policies/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(policy)
        return try await execute(request)
    }
    
    public func updatePolicy(policyNo: Int, policy: PolicyCreate) async throws -> Policy {
        let url = baseURL.appendingPathComponent("policies/\(policyNo)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(policy)
        return try await execute(request)
    }
    
    public func deletePolicy(policyNo: Int) async throws {
        let url = baseURL.appendingPathComponent("policies/\(policyNo)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        try await executeNoContent(request)
    }

    // MARK: - Clients API
    
    public func getClients() async throws -> [Client] {
        let url = baseURL.appendingPathComponent("clients/")
        return try await execute(URLRequest(url: url))
    }
    
    public func createClient(_ client: ClientCreate) async throws -> Client {
        let url = baseURL.appendingPathComponent("clients/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(client)
        return try await execute(request)
    }

    // MARK: - Vessels API
    
    public func getVessels() async throws -> [Vessel] {
        let url = baseURL.appendingPathComponent("vessels/")
        return try await execute(URLRequest(url: url))
    }

    // MARK: - Claims API
    
    public func getClaims(policyNo: Int? = nil) async throws -> [Claim] {
        var components = URLComponents(url: baseURL.appendingPathComponent("claims/"), resolvingAgainstBaseURL: true)!
        if let pNo = policyNo {
            components.queryItems = [URLQueryItem(name: "policy_no", value: "\(pNo)")]
        }
        return try await execute(URLRequest(url: components.url!))
    }
    
    public func createClaim(_ claim: ClaimCreate) async throws -> Claim {
        let url = baseURL.appendingPathComponent("claims/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(claim)
        return try await execute(request)
    }

    // MARK: - Junction API (Composite Keys)
    
    public func getReinsuranceShares(policyNo: Int) async throws -> [ReinsuredBy] {
        var components = URLComponents(url: baseURL.appendingPathComponent("reinsured-by/"), resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "policy_no", value: "\(policyNo)")]
        return try await execute(URLRequest(url: components.url!))
    }
    
    public func deleteReinsuranceShare(policyNo: Int, reinsurerId: Int) async throws {
        let url = baseURL.appendingPathComponent("reinsured-by/\(policyNo)/\(reinsurerId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        try await executeNoContent(request)
    }
}
```

---

## 5. 📱 SwiftUI Integration Example

Here is a SwiftUI implementation showing policy listings, badge filters, pull-to-refresh, error alert handling, and creation:

```swift
import SwiftUI

@MainActor
@Observable
final class PolicyViewModel {
    var policies: [Policy] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var selectedType: PolicyType? = nil
    
    private let client = MarineInsuranceAPIClient.shared

    func loadPolicies() async {
        isLoading = true
        errorMessage = nil
        do {
            policies = try await client.getPolicies(policyType: selectedType)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func deletePolicy(policyNo: Int) async {
        do {
            try await client.deletePolicy(policyNo: policyNo)
            policies.removeAll { $0.policy_no == policyNo }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct PolicyDashboardView: View {
    @State private var viewModel = PolicyViewModel()
    @State private var showCreateSheet: Bool = false

    public var body: some View {
        NavigationStack {
            VStack {
                // Filter Picker
                Picker("Policy Type", selection: $viewModel.selectedType) {
                    Text("All Policies").tag(PolicyType?.none)
                    ForEach(PolicyType.allCases) { type in
                        Text(type.displayName).tag(PolicyType?.some(type))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: viewModel.selectedType) {
                    Task { await viewModel.loadPolicies() }
                }

                if viewModel.isLoading && viewModel.policies.isEmpty {
                    ProgressView("Loading policies...")
                        .frame(maxHeight: .infinity)
                } else if viewModel.policies.isEmpty {
                    ContentUnavailableView("No Policies Found", systemImage: "doc.text.magnifyingglass")
                } else {
                    List {
                        ForEach(viewModel.policies) { policy in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Policy #\(policy.policy_no)")
                                        .font(.headline)
                                    Spacer()
                                    if let type = policy.policy_type {
                                        Text(type.rawValue)
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.blue.opacity(0.15))
                                            .foregroundStyle(.blue)
                                            .clipShape(Capsule())
                                    }
                                }
                                
                                HStack {
                                    Text("Premium: $\(policy.premium ?? "0.00")")
                                    Spacer()
                                    Text("Coverage: $\(policy.sum_insured ?? "0.00")")
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let policyNo = viewModel.policies[index].policy_no
                                Task { await viewModel.deletePolicy(policyNo: policyNo) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Marine Policies")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await viewModel.loadPolicies()
            }
            .sheet(isPresented: $showCreateSheet) {
                CreatePolicySheetView {
                    Task { await viewModel.loadPolicies() }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button("OK") { viewModel.errorMessage = nil }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .task {
                await viewModel.loadPolicies()
            }
        }
    }
}

struct CreatePolicySheetView: View {
    @Environment(\.dismiss) private var dismiss
    var onCreated: () -> Void
    
    @State private var policyType: PolicyType = .hull
    @State private var premium: String = "25000.00"
    @State private var sumInsured: String = "1000000.00"
    @State private var isSubmitting: Bool = false
    @State private var errorText: String? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Policy Information") {
                    Picker("Type", selection: $policyType) {
                        ForEach(PolicyType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    TextField("Premium ($)", text: $premium)
                        .keyboardType(.decimalPad)
                    TextField("Sum Insured ($)", text: $sumInsured)
                        .keyboardType(.decimalPad)
                }
                
                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle("New Policy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await savePolicy() }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }
    
    private func savePolicy() async {
        isSubmitting = true
        errorText = nil
        do {
            let newPolicy = PolicyCreate(
                policy_type: policyType,
                issue_date: "2026-10-15",
                expiry_date: "2027-10-14",
                premium: premium,
                sum_insured: sumInsured,
                client_id: 1, // sample client from seed
                vessel_id: 1  // sample vessel from seed
            )
            _ = try await MarineInsuranceAPIClient.shared.createPolicy(newPolicy)
            onCreated()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
        isSubmitting = false
    }
}
```

---

## 6. 🗃️ Preloaded Seed Data Reference

The database comes pre-seeded with test data so you can test views right away:

| Entity | Preloaded Records | Test IDs |
|---|---|---|
| **Clients** | Oceanic Shipping Corp, Atlantic Cargo Lines, Pacific Global Logistics | `client_id`: 1, 2, 3 |
| **Vessels** | Ever Pioneer (Panama), Nordic Star (Liberia), Pacific Voyager (Singapore) | `vessel_id`: 1, 2, 3 |
| **Brokers** | Apex Maritime Brokers Ltd, BlueWave Risk Solutions | `broker_id`: 1, 2 |
| **Underwriters** | James Montgomery, Sarah Jenkins, Marcus Zhao | `emp_id`: 1, 2, 3 |
| **Policies** | Policy 1 (`HULL`, $50M), Policy 2 (`CARGO`, $2.5M), Policy 3 (`PI`, $100M) | `policy_no`: 1, 2, 3 |
| **Claims** | Claim 1 ($185k on Policy 2), Claim 2 ($450k on Policy 1) | `claim_id`: 1, 2 |
| **Reinsured By** | Policy 1 backed by Swiss Re (40%) and Munich Re (35%) | Composite: `1/1`, `1/2` |

---

## 7. 📖 Complete REST Endpoint Catalog

| Group | Method | Endpoint Path | Description | Status Codes |
|---|---|---|---|---|
| **Health** | `GET` | `/api/health` | Service health & database status | `200` |
| **Clients** | `GET` | `/api/clients/` | List all clients (`?skip=0&limit=100`) | `200` |
| | `GET` | `/api/clients/{id}` | Get client by ID | `200`, `404` |
| | `POST` | `/api/clients/` | Create client | `201` |
| | `PUT` | `/api/clients/{id}` | Update client | `200`, `404` |
| | `DELETE`| `/api/clients/{id}` | Delete client | `204`, `404` |
| **Brokers** | `GET` | `/api/brokers/` | List brokers | `200` |
| | `GET` | `/api/brokers/{id}` | Get broker | `200`, `404` |
| | `POST` | `/api/brokers/` | Create broker (licence_no unique) | `201`, `400` |
| | `PUT` | `/api/brokers/{id}` | Update broker | `200`, `400`, `404` |
| | `DELETE`| `/api/brokers/{id}` | Delete broker | `204`, `404` |
| **Surveyors** | `GET` | `/api/surveyors/` | List surveyors | `200` |
| | `POST` | `/api/surveyors/` | Create surveyor | `201` |
| | `GET/PUT/DEL`| `/api/surveyors/{id}` | Read / Update / Delete surveyor | `200`, `204`, `404` |
| **Reinsurers** | `GET` | `/api/reinsurers/` | List reinsurers | `200` |
| | `POST` | `/api/reinsurers/` | Create reinsurer | `201` |
| | `GET/PUT/DEL`| `/api/reinsurers/{id}` | Read / Update / Delete reinsurer | `200`, `204`, `404` |
| **Cargos** | `GET` | `/api/cargos/` | List cargos | `200` |
| | `POST` | `/api/cargos/` | Create cargo | `201` |
| | `GET/PUT/DEL`| `/api/cargos/{id}` | Read / Update / Delete cargo | `200`, `204`, `404` |
| **Vessels** | `GET` | `/api/vessels/` | List vessels | `200` |
| | `POST` | `/api/vessels/` | Create vessel (imo_number unique) | `201`, `400` |
| | `GET/PUT/DEL`| `/api/vessels/{id}` | Read / Update / Delete vessel | `200`, `400`, `404` |
| **Departments**| `GET/POST`| `/api/departments/` | List / Create departments | `200`, `201` |
| | `GET/PUT/DEL`| `/api/departments/{id}` | Read / Update / Delete department | `200`, `204`, `404` |
| **Underwriters**| `GET` | `/api/underwriters/?dept_id={id}`| List underwriters with optional dept filter | `200` |
| | `POST` | `/api/underwriters/` | Create underwriter | `201`, `400` |
| | `GET/PUT/DEL`| `/api/underwriters/{id}` | Read / Update / Delete underwriter | `200`, `400`, `404` |
| **Voyages** | `GET` | `/api/voyages/?vessel_id={id}` | List voyages with optional vessel filter | `200` |
| | `POST` | `/api/voyages/` | Create voyage | `201`, `400` |
| | `GET/PUT/DEL`| `/api/voyages/{id}` | Read / Update / Delete voyage | `200`, `400`, `404` |
| **Policies** | `GET` | `/api/policies/?policy_type=HULL&client_id=1` | Filterable list of policies | `200` |
| | `GET` | `/api/policies/{no}` | Get policy details | `200`, `404` |
| | `POST` | `/api/policies/` | Create policy | `201`, `400` |
| | `PUT` | `/api/policies/{no}` | Update policy | `200`, `400`, `404` |
| | `DELETE`| `/api/policies/{no}` | Delete policy | `204`, `404` |
| **Claims** | `GET` | `/api/claims/?policy_no={no}` | List claims (optional policy filter) | `200` |
| | `GET` | `/api/claims/{id}` | Get claim by ID | `200`, `404` |
| | `POST` | `/api/claims/` | Create claim | `201`, `400` |
| | `PUT` | `/api/claims/{id}` | Update claim | `200`, `400`, `404` |
| | `DELETE`| `/api/claims/{id}` | Delete claim | `204`, `404` |
| **Reinsured By**| `GET` | `/api/reinsured-by/?policy_no={no}` | List reinsurance mappings | `200` |
| | `POST` | `/api/reinsured-by/` | Create reinsurance mapping | `201`, `400` |
| | `GET/PUT/DEL`| `/api/reinsured-by/{policy_no}/{reinsurer_id}` | Read / Update share / Delete link | `200`, `204`, `404` |
| **Assessed By**| `GET/POST`| `/api/assessed-by/` | List / Link surveyor to claim | `200`, `201`, `400` |
| | `GET/DEL`| `/api/assessed-by/{claim_id}/{surveyor_id}` | Get / Delete assessment link | `200`, `204`, `404` |
| **Carries** | `GET/POST`| `/api/carries/` | List / Link cargo to voyage | `200`, `201`, `400` |
| | `GET/DEL`| `/api/carries/{voyage_id}/{cargo_id}` | Get / Delete voyage-cargo link | `200`, `204`, `404` |


## Underwriting additions

Policy responses now include optional `underwriting_decision`, `risk_score`,
`warranties`, `awrp_surcharge` (a decimal string), and `underwriting_report`.
The report includes `vessel_age`, `voyage_id`, `risk_factors`,
`warranties_required`, `retrieved_guidelines`, and `recommended_premium`.
These fields are server-owned and cannot be set through policy create/update.

`APIClient.assessPolicy(_:vesselAge:voyageId:)` posts to
`policies/{policy_no}/submit-underwriting` and returns the updated policy.
The policy detail screen saves that response in the Ledger and disables Bind
for `DECLINE` and `REFER_TO_SENIOR`. The backend enforces both decisions too.

List endpoints still return arrays unless the caller explicitly passes `page`.
The existing client needs no pagination response changes. Default DELETE behavior
and database cascades are unchanged. See the README for optional archiving and
the limits of the local underwriting demo.
