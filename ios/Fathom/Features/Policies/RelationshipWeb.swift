import SwiftUI

/// One record linked to the policy, shown as a node around it.
struct PolicyWebNode: Identifiable {
    let id: String
    let kind: String
    let name: String
    /// The EER relationship, read from the record towards the policy ("holds").
    let relation: String
    let symbol: String
    let tint: Color
    let route: AppRoute

    /// Client, broker, underwriter, subject, reinsurers, then claims.
    static func nodes(for links: PolicyLinks) -> [PolicyWebNode] {
        var nodes: [PolicyWebNode] = []
        if let client = links.client {
            nodes.append(PolicyWebNode(id: "client", kind: "Client", name: client.name, relation: "holds",
                                 symbol: NetworkKind.client.symbol, tint: NetworkKind.client.tint,
                                 route: .network(NetworkRoute(kind: .client, key: client.id))))
        }
        if let broker = links.broker {
            nodes.append(PolicyWebNode(id: "broker", kind: "Broker", name: broker.agencyName, relation: "placed by",
                                 symbol: NetworkKind.broker.symbol, tint: NetworkKind.broker.tint,
                                 route: .network(NetworkRoute(kind: .broker, key: broker.id))))
        }
        if let uw = links.underwriter {
            nodes.append(PolicyWebNode(id: "underwriter", kind: "Underwriter", name: uw.name, relation: "underwritten by",
                                 symbol: NetworkKind.underwriter.symbol, tint: NetworkKind.underwriter.tint,
                                 route: .network(NetworkRoute(kind: .underwriter, key: uw.id))))
        }
        if let vessel = links.vessel {
            nodes.append(PolicyWebNode(id: "vessel", kind: "Vessel", name: vessel.name, relation: "covers",
                                 symbol: PolicyType.hull.symbol, tint: PolicyType.hull.tint, route: .vessel(vessel.id)))
        }
        if let cargo = links.cargo {
            nodes.append(PolicyWebNode(id: "cargo", kind: "Cargo", name: cargo.description ?? "Cargo #\(cargo.id)", relation: "covers",
                                 symbol: PolicyType.cargo.symbol, tint: PolicyType.cargo.tint, route: .cargo(cargo.id)))
        }
        for share in links.shares {
            let name = links.reinsurers[share.reinsurerId]?.name ?? "Reinsurer #\(share.reinsurerId)"
            let percent = share.share.map { " \(PolicyFormat.percent($0))" } ?? ""
            nodes.append(PolicyWebNode(id: "reinsurer-\(share.reinsurerId)", kind: "Reinsurer", name: name,
                                 relation: "reinsured by\(percent)",
                                 symbol: NetworkKind.reinsurer.symbol, tint: NetworkKind.reinsurer.tint,
                                 route: .network(NetworkRoute(kind: .reinsurer, key: share.reinsurerId))))
        }
        for claim in links.claims {
            nodes.append(PolicyWebNode(id: "claim-\(claim.claimId)", kind: "Claim", name: "Claim #\(claim.claimId)",
                                 relation: "claim on", symbol: "lifepreserver.fill", tint: Theme.coral,
                                 route: .claim(claim.claimId)))
        }
        return nodes
    }
}

/// The policy in the centre with every related record orbiting it, each joined by
/// a line named after its relationship. Tapping a node opens that record.
struct RelationshipWeb: View {
    let policy: Policy
    let nodes: [PolicyWebNode]

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.36
            ZStack {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    let point = position(index, center: center, radius: radius)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point)
                    }
                    .trim(from: 0, to: shown ? 1 : 0)
                    .stroke(node.tint.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: node.kind == "Claim" ? [4, 4] : []))
                    .animation(animation(index), value: shown)

                    edgeLabel(node.relation, from: center, to: point, tint: node.tint)
                        .opacity(shown ? 1 : 0)
                        .animation(animation(index, after: 0.2), value: shown)
                }

                hub
                    .position(center)

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    NavigationLink(value: node.route) {
                        NodeBubble(node: node)
                    }
                    .buttonStyle(.plain)
                    .position(shown ? position(index, center: center, radius: radius) : center)
                    .scaleEffect(shown ? 1 : 0.2)
                    .opacity(shown ? 1 : 0)
                    .animation(animation(index), value: shown)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { shown = true }
    }

    private var hub: some View {
        let type = policy.policyType ?? .hull
        return VStack(spacing: 2) {
            PolicyArt(type: type)
                .frame(width: 44, height: 34)
            Text("#\(policy.policyNo)")
                .font(.system(.caption, design: .monospaced, weight: .bold))
        }
        .frame(width: 84, height: 84)
        .glassEffect(.regular.tint(type.tint.opacity(0.3)), in: .circle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(policy.numberTitle)
    }

    private func animation(_ index: Int, after extra: Double = 0) -> Animation? {
        reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.3).delay(0.15 + extra + Double(index) * 0.06)
    }

    /// Nodes sit evenly on a circle, starting at the top.
    private func position(_ index: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + Double(index) / Double(max(nodes.count, 1)) * 2 * .pi
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    /// Relationship name laid along its line, flipped so it never reads upside down.
    private func edgeLabel(_ text: String, from start: CGPoint, to end: CGPoint, tint: Color) -> some View {
        var angle = atan2(end.y - start.y, end.x - start.x)
        if abs(angle) > .pi / 2 { angle += .pi }
        let middle = CGPoint(x: start.x + (end.x - start.x) * 0.56, y: start.y + (end.y - start.y) * 0.56)
        return Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.abyss.opacity(0.85), in: .capsule)
            .rotationEffect(.radians(angle))
            .position(middle)
            .accessibilityHidden(true)
    }
}

private struct NodeBubble: View {
    let node: PolicyWebNode

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: node.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(node.tint)
                .frame(width: 42, height: 42)
                .glassEffect(.regular.tint(node.tint.opacity(0.25)).interactive(), in: .circle)
            Text(node.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 82)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(node.kind): \(node.name)")
        .accessibilityHint("Policy \(node.relation)")
    }
}

/// The same links as a plain list, for VoiceOver and large text sizes.
struct RelationshipList: View {
    let nodes: [PolicyWebNode]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(nodes) { node in
                NavigationLink(value: node.route) {
                    HStack(spacing: 12) {
                        Image(systemName: node.symbol)
                            .foregroundStyle(node.tint)
                            .frame(width: 36, height: 36)
                            .background(node.tint.opacity(0.15), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(node.kind) · \(node.relation)")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                            Text(node.name)
                                .font(.rounded(.subheadline, weight: .semibold))
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .padding(10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
