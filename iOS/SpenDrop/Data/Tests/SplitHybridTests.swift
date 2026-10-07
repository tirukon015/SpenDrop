import Foundation
import SwiftData

/// Hybrid Split: group fixed amounts + individual fixed amounts + the remaining amount split equally
/// (Common/BusinessRules/split-hybrid.md). `--run-split-hybrid-tests`. In-memory stores only.
@MainActor
public enum SplitHybridTests {
    // MARK: Shared vectors — keep identical to Common/BusinessRules/split-hybrid-vectors.json

    struct Vector {
        let name: String; let total: Int; let people: [String]; let payer: String?
        let groups: [(amount: Int?, members: [String])]
        let individuals: [(person: String?, amount: Int?)]
        let remaining: [String]
        let shares: [Int]?; let groupAllocation: Int?; let individualAllocation: Int?; let remainingMinor: Int?; let problem: String?
    }

    static let vectors: [Vector] = [
        Vector(name: "Request example: group RM100 Riad+Bijoy, Bijoy +RM20, rest You+Riad+Bijoy", total: 20000, people: ["Riad", "Bijoy"], payer: nil,
               groups: [(10000, ["Riad", "Bijoy"])], individuals: [("Bijoy", 2000)], remaining: ["Me", "Riad", "Bijoy"],
               shares: [2667, 7667, 9666], groupAllocation: 10000, individualAllocation: 2000, remainingMinor: 8000, problem: nil),
        Vector(name: "Group with 2 people, person only in group", total: 10000, people: ["A", "B"], payer: nil,
               groups: [(6000, ["A", "B"])], individuals: [], remaining: ["Me"],
               shares: [4000, 3000, 3000], groupAllocation: 6000, individualAllocation: 0, remainingMinor: 4000, problem: nil),
        Vector(name: "Group with 3 people, uneven division", total: 15000, people: ["A", "B", "C"], payer: nil,
               groups: [(10000, ["A", "B", "C"])], individuals: [], remaining: ["Me"],
               shares: [5000, 3334, 3333, 3333], groupAllocation: 10000, individualAllocation: 0, remainingMinor: 5000, problem: nil),
        Vector(name: "Group including Me, uneven (Me first when I paid)", total: 10000, people: ["A", "B"], payer: nil,
               groups: [(1000, ["Me", "A", "B"])], individuals: [], remaining: ["A", "B"],
               shares: [334, 4833, 4833], groupAllocation: 1000, individualAllocation: 0, remainingMinor: 9000, problem: nil),
        Vector(name: "Individual fixed for one person", total: 10000, people: ["A"], payer: nil,
               groups: [], individuals: [("A", 2000)], remaining: ["Me", "A"],
               shares: [4000, 6000], groupAllocation: 0, individualAllocation: 2000, remainingMinor: 8000, problem: nil),
        Vector(name: "Multiple individual fixed amounts", total: 20000, people: ["Riad", "Bijoy"], payer: nil,
               groups: [], individuals: [("Riad", 2000), ("Bijoy", 3000)], remaining: ["Me", "Riad", "Bijoy"],
               shares: [5000, 7000, 8000], groupAllocation: 0, individualAllocation: 5000, remainingMinor: 15000, problem: nil),
        Vector(name: "Person only in individual fixed", total: 10000, people: ["A", "B"], payer: nil,
               groups: [], individuals: [("B", 1500)], remaining: ["Me", "A"],
               shares: [4250, 4250, 1500], groupAllocation: 0, individualAllocation: 1500, remainingMinor: 8500, problem: nil),
        Vector(name: "Group + individual exactly equal the total", total: 10000, people: ["A", "B"], payer: nil,
               groups: [(8000, ["A", "B"])], individuals: [("B", 2000)], remaining: [],
               shares: [0, 4000, 6000], groupAllocation: 8000, individualAllocation: 2000, remainingMinor: 0, problem: nil),
        Vector(name: "Remaining zero with a remaining group", total: 10000, people: ["A", "B"], payer: nil,
               groups: [(8000, ["A", "B"])], individuals: [("B", 2000)], remaining: ["Me"],
               shares: [0, 4000, 6000], groupAllocation: 8000, individualAllocation: 2000, remainingMinor: 0, problem: nil),
        Vector(name: "Fixed allocations exceed the total", total: 10000, people: ["A", "B"], payer: nil,
               groups: [(8000, ["A", "B"])], individuals: [("A", 3000)], remaining: ["Me"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Fixed allocations exceed the transaction total by RM 10.00."),
        Vector(name: "Two groups + remaining", total: 20000, people: ["Riad", "Bijoy"], payer: nil,
               groups: [(10000, ["Riad", "Bijoy"]), (6000, ["Me", "Riad"])], individuals: [], remaining: ["Me", "Riad", "Bijoy"],
               shares: [4334, 9333, 6333], groupAllocation: 16000, individualAllocation: 0, remainingMinor: 4000, problem: nil),
        Vector(name: "Decimals: uneven group, individual, remaining", total: 15055, people: ["A", "B"], payer: nil,
               groups: [(5001, ["A", "B"])], individuals: [("A", 1250)], remaining: ["Me", "B"],
               shares: [4402, 3751, 6902], groupAllocation: 5001, individualAllocation: 1250, remainingMinor: 8804, problem: nil),
        Vector(name: "Someone else paid: leftover sen in participant order", total: 10000, people: ["A", "B"], payer: "A",
               groups: [(1001, ["A", "B"])], individuals: [], remaining: ["Me", "A", "B"],
               shares: [3000, 3501, 3499], groupAllocation: 1001, individualAllocation: 0, remainingMinor: 8999, problem: nil),
        Vector(name: "Empty starter group is ignored", total: 10000, people: ["A"], payer: nil,
               groups: [(nil, [])], individuals: [("A", 2000)], remaining: ["Me", "A"],
               shares: [4000, 6000], groupAllocation: 0, individualAllocation: 2000, remainingMinor: 8000, problem: nil),
        Vector(name: "Nothing fixed", total: 10000, people: ["A"], payer: nil,
               groups: [], individuals: [], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Add a group fixed amount or an individual fixed amount."),
        Vector(name: "Group without members", total: 10000, people: ["A"], payer: nil,
               groups: [(1000, [])], individuals: [], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Choose who shares group fixed amount 1."),
        Vector(name: "Group without an amount", total: 10000, people: ["A"], payer: nil,
               groups: [(nil, ["A"])], individuals: [], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Enter the amount for group fixed amount 1."),
        Vector(name: "Negative group amount", total: 10000, people: ["A"], payer: nil,
               groups: [(-500, ["A"])], individuals: [], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Enter the amount for group fixed amount 1."),
        Vector(name: "Second group problem is numbered", total: 10000, people: ["A"], payer: nil,
               groups: [(1000, ["A"]), (2000, [])], individuals: [], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Choose who shares group fixed amount 2."),
        Vector(name: "Problems are checked group by group", total: 10000, people: ["A"], payer: nil,
               groups: [(1000, []), (nil, ["A"])], individuals: [], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Choose who shares group fixed amount 1."),
        Vector(name: "Individual without a person", total: 10000, people: ["A"], payer: nil,
               groups: [], individuals: [(nil, 1000)], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Choose a person for each individual fixed amount."),
        Vector(name: "Individual without an amount", total: 10000, people: ["A"], payer: nil,
               groups: [], individuals: [("A", nil)], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Enter the individual fixed amount for A."),
        Vector(name: "Individual for Me without an amount", total: 10000, people: ["A"], payer: nil,
               groups: [], individuals: [("Me", nil)], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Enter the individual fixed amount for You."),
        Vector(name: "Two individual amounts for the same person", total: 10000, people: ["A"], payer: nil,
               groups: [], individuals: [("A", 1000), ("A", 500)], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "A already has an individual fixed amount."),
        Vector(name: "Individual rows are checked row by row", total: 10000, people: ["A", "B"], payer: nil,
               groups: [], individuals: [("A", nil), (nil, 500)], remaining: ["Me", "A", "B"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Enter the individual fixed amount for A."),
        Vector(name: "Money left and nobody shares it", total: 20000, people: ["Riad", "Bijoy"], payer: nil,
               groups: [(10000, ["Riad", "Bijoy"])], individuals: [], remaining: [],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "RM 100.00 is left after the fixed allocations. Choose who shares the remaining amount."),
        Vector(name: "A person in no layer", total: 10000, people: ["A", "B"], payer: nil,
               groups: [], individuals: [("A", 1000)], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "B isn't in any part of the split. Add them to an allocation or remove them."),
        Vector(name: "Only Me in the split", total: 10000, people: [], payer: nil,
               groups: [], individuals: [("Me", 1000)], remaining: ["Me"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Add at least one other person."),
        Vector(name: "No total yet", total: 0, people: ["A"], payer: nil,
               groups: [(1000, ["A"])], individuals: [], remaining: ["Me", "A"],
               shares: nil, groupAllocation: nil, individualAllocation: nil, remainingMinor: nil, problem: "Enter the expense amount first.")
    ]

    static func id(_ d: SplitDraft, _ name: String) -> UUID {
        d.participants.first { $0.isMe ? name == "Me" : $0.name == name }!.id
    }

    static func text(_ minor: Int?) -> String { minor.map { SplitDraft.text(fromMinor: $0) } ?? "" }

    /// Builds the draft the way a user would: add people, turn Hybrid Split on, fill the starter group, add more groups
    /// and individual rows, tick who shares the remaining amount.
    static func draft(_ v: Vector, in ctx: ModelContext) -> SplitDraft {
        var d = SplitDraft()
        var profiles: [String: PayBookProfile] = [:]
        for name in v.people {
            let p = PayBookProfile(name: name); ctx.insert(p); profiles[name] = p
            d.add(p)
        }
        if let payer = v.payer { d.payer = profiles[payer] }
        d.setHybrid(true)
        for (n, group) in v.groups.enumerated() {
            let groupID = n == 0 ? d.hybridGroups[0].id : d.addHybridGroup()
            d.setGroupAmountText(text(group.amount), for: groupID)
            for member in group.members { d.setGroupMember(true, participant: id(d, member), group: groupID) }
        }
        for individual in v.individuals {
            let row = d.addIndividual()
            d.setIndividualPerson(individual.person.map { id(d, $0) }, for: row)
            d.setIndividualAmountText(text(individual.amount), for: row)
        }
        for participant in d.participants {
            d.setInRemainder(v.remaining.contains(participant.isMe ? "Me" : participant.name), participant: participant.id)
        }
        return d
    }

    static func describe(_ shares: [Int]?) -> String { shares.map { "\($0)" } ?? "nil" }

    public static func runAllTests() -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Hybrid split") { results.append($0) }

        // 1–27. Shared vectors
        for v in vectors {
            let ctx = TestKit.context()
            let d = draft(v, in: ctx)
            let shares = d.shares(totalMinor: v.total)
            let problem = d.problem(totalMinor: v.total)
            let split = try? d.hybridSplit(totalMinor: v.total).get()
            let passed: Bool
            if let expected = v.shares {
                passed = shares == expected && problem == nil && expected.reduce(0, +) == v.total &&
                         split?.groupAllocationMinor == v.groupAllocation && split?.individualAllocationMinor == v.individualAllocation &&
                         split?.remainingMinor == v.remainingMinor && d.groupAllocationMinor == v.groupAllocation &&
                         d.individualAllocationMinor == v.individualAllocation && d.hybridRemainingMinor(totalMinor: v.total) == v.remainingMinor
            } else {
                passed = shares == nil && problem == v.problem && !d.isValid(totalMinor: v.total)
            }
            t.check("Vector: \(v.name)", passed,
                    expected: v.shares.map { "\($0) group=\(v.groupAllocation ?? -1) individual=\(v.individualAllocation ?? -1) remaining=\(v.remainingMinor ?? -1)" } ?? (v.problem ?? ""),
                    actual: shares.map { "\($0) group=\(split?.groupAllocationMinor ?? -1) individual=\(split?.individualAllocationMinor ?? -1) remaining=\(split?.remainingMinor ?? -1)" } ?? (problem ?? "nil"))
        }

        let ctx = TestKit.context()
        let riad = DebtSettlementTests.person("Riad", in: ctx), bijoy = DebtSettlementTests.person("Bijoy", in: ctx)
        let vijay = DebtSettlementTests.person("Vijay", in: ctx), labib = DebtSettlementTests.person("Labib", in: ctx)

        /// The request example: RM200; group RM100 between Riad + Bijoy; Bijoy +RM20; the rest by You, Riad, Bijoy.
        func example() -> SplitDraft {
            var d = SplitDraft(); d.add(riad); d.add(bijoy)
            d.setHybrid(true)
            let g = d.hybridGroups[0].id
            d.setGroupAmountText("100", for: g)
            d.setGroupMember(true, participant: id(d, "Riad"), group: g); d.setGroupMember(true, participant: id(d, "Bijoy"), group: g)
            let row = d.addIndividual()
            d.setIndividualPerson(id(d, "Bijoy"), for: row); d.setIndividualAmountText("20", for: row)
            return d
        }

        // Combinations the request lists (beyond the vectors)
        do {
            // Only group fixed amounts: two groups cover the total exactly, nobody shares a remainder.
            var onlyGroups = SplitDraft(); onlyGroups.add(riad); onlyGroups.add(bijoy); onlyGroups.add(vijay)
            onlyGroups.setHybrid(true)
            let g1 = onlyGroups.hybridGroups[0].id
            onlyGroups.setGroupAmountText("90", for: g1)
            for name in ["Me", "Riad", "Bijoy"] { onlyGroups.setGroupMember(true, participant: id(onlyGroups, name), group: g1) }
            let g2 = onlyGroups.addHybridGroup()
            onlyGroups.setGroupAmountText("10", for: g2); onlyGroups.setGroupMember(true, participant: id(onlyGroups, "Vijay"), group: g2)
            for p in onlyGroups.participants { onlyGroups.setInRemainder(false, participant: p.id) }
            // Only individual fixed amounts, covering the total.
            var onlyIndividuals = SplitDraft(); onlyIndividuals.add(riad)
            onlyIndividuals.setHybrid(true)
            for (name, amount) in [("Me", "40"), ("Riad", "60")] {
                let row = onlyIndividuals.addIndividual()
                onlyIndividuals.setIndividualPerson(id(onlyIndividuals, name), for: row); onlyIndividuals.setIndividualAmountText(amount, for: row)
            }
            for p in onlyIndividuals.participants { onlyIndividuals.setInRemainder(false, participant: p.id) }
            // Only the remaining amount: that is Split Equally, so Hybrid Split asks for a fixed amount.
            var onlyRemaining = SplitDraft(); onlyRemaining.add(riad); onlyRemaining.setHybrid(true)
            // A person in a group AND an individual amount AND the remaining amount (all three layers).
            let all = example()
            let split = try? all.hybridSplit(totalMinor: 20000).get()
            t.check("Only groups (90 by 3 + 10 to Vijay = RM100) → 30/30/30/10; only individuals 40 + 60; only remaining → 'Add a group fixed amount or an individual fixed amount.'; Bijoy in all three layers = 50 group + 20 individual + 26.66 remaining",
                    onlyGroups.shares(totalMinor: 10000) == [3000, 3000, 3000, 1000] &&
                    onlyIndividuals.shares(totalMinor: 10000) == [4000, 6000] &&
                    onlyRemaining.problem(totalMinor: 10000) == "Add a group fixed amount or an individual fixed amount." &&
                    split?.groupTotal(for: 2) == 5000 && split?.individualParts[2] == 2000 && split?.remainingParts[2] == 2666 &&
                    split?.shares == [2667, 7667, 9666],
                    expected: "[3000,3000,3000,1000] [4000,6000] problem 8, Bijoy 5000+2000+2666",
                    actual: "\(describe(onlyGroups.shares(totalMinor: 10000))) \(describe(onlyIndividuals.shares(totalMinor: 10000))) \(onlyRemaining.problem(totalMinor: 10000) ?? "nil")")
        }

        // Turning on / off
        do {
            var d = SplitDraft(); d.add(riad); d.add(bijoy); d.method = .parts
            d.setHybrid(true)
            let fresh = d.hybridGroups.count == 1 && d.hybridGroups[0].isBlank && d.hybridIndividuals.isEmpty &&
                        d.remainderIDs == Set(d.participants.map(\.id))
            let problem = d.problem(totalMinor: 9000)
            d.setHybrid(false)
            t.check("Turning on: one empty group, no individuals, everyone (Me too) shares the rest; off returns to Parts with the same people",
                    fresh && problem == "Add a group fixed amount or an individual fixed amount." && d.method == .parts && !d.usesHybrid &&
                    d.shares(totalMinor: 9000) == [3000, 3000, 3000],
                    expected: "fresh, problem 8, Parts again", actual: "\(fresh) \(problem ?? "nil") \(d.method)")
        }

        // Without Hybrid Split nothing changes
        do {
            var equal = SplitDraft(); equal.add(riad); equal.add(bijoy)
            let before = equal.shares(totalMinor: 10000)
            var toggled = equal; toggled.setHybrid(true); toggled.setHybrid(false)
            var custom = SplitDraft(); custom.add(riad); custom.add(bijoy); custom.useCustomAmounts(totalMinor: 10000)
            custom.setAmountText("50", for: id(custom, "Riad"), totalMinor: 10000)
            var customToggled = custom; customToggled.setHybrid(true); customToggled.setHybrid(false)
            let saved = Expense(amount: 100, merchant: "Plain"); ctx.insert(saved)
            let savedOK = custom.apply(to: saved, in: ctx)
            t.check("Without Hybrid Split: Equal 33.34/33.33/33.33, Custom 25/50/25; on→off keeps every amount; a normal split saves no rule",
                    before == [3334, 3333, 3333] && toggled.shares(totalMinor: 10000) == before &&
                    custom.shares(totalMinor: 10000) == [2500, 5000, 2500] && customToggled.shares(totalMinor: 10000) == [2500, 5000, 2500] &&
                    savedOK && saved.splitMethod == .amounts && saved.splitRule == nil,
                    expected: "unchanged, splitRule nil", actual: "\(describe(before)) \(describe(customToggled.shares(totalMinor: 10000))) rule=\(saved.splitRule ?? "nil")")
        }

        // Live: amounts and people change the result immediately
        do {
            var d = example()
            let s1 = d.shares(totalMinor: 20000)
            d.setGroupAmountText("120", for: d.hybridGroups[0].id)          // 60/60 group, 60 left by 3
            let s2 = d.shares(totalMinor: 20000)
            d.setIndividualAmountText("35.50", for: d.hybridIndividuals[0].id) // 120 + 35.50, 44.50 by 3
            let s3 = d.shares(totalMinor: 20000)
            let s4 = d.shares(totalMinor: 30000)                                // total changes too
            d.add(vijay)                                                        // joins the remaining amount only
            let vijayID = id(d, "Vijay")
            let joined = d.remainderIDs.contains(vijayID) && !d.hybridGroups[0].memberIDs.contains(vijayID) &&
                         !d.hybridIndividuals.contains { $0.participantID == vijayID }
            let s5 = d.shares(totalMinor: 20000)                                // 44.50 by 4
            let row = d.addIndividual(); d.setIndividualPerson(vijayID, for: row); d.setIndividualAmountText("4.50", for: row)
            d.setGroupMember(true, participant: vijayID, group: d.hybridGroups[0].id)
            let s6 = d.shares(totalMinor: 20000)                                // 120 by 3, 35.50 + 4.50, 40 by 4
            d.remove(id: vijayID)                                               // out of the group, his row and the remainder
            let removed = !d.hybridGroups[0].memberIDs.contains(vijayID) && d.hybridIndividuals.count == 1 && !d.remainderIDs.contains(vijayID)
            let s7 = d.shares(totalMinor: 20000)
            let all = [s1, s2, s3, s5, s6, s7]
            t.check("Live: group 100→120, Bijoy 20→35.50, total 200→300, Vijay added (remaining only), given 4.50 + a group place, removed again — exact every time",
                    s1 == [2667, 7667, 9666] && s2 == [2000, 8000, 10000] && s3 == [1484, 7483, 11033] && s4 == [4817, 10817, 14366] &&
                    s5 == [1113, 7113, 10662, 1112] && s6 == [1000, 5000, 8550, 5450] && s7 == s3 && joined && removed &&
                    all.allSatisfy { ($0?.reduce(0, +) ?? -1) == 20000 },
                    expected: "exact after every change", actual: "\(all.map(describe)) \(describe(s4)) joined=\(joined) removed=\(removed)")
        }

        // Paid for someone has no Hybrid Split
        do {
            var d = example()
            d.purpose = .paidFor
            let off = !d.hybrid && !d.usesHybrid
            d.setHybrid(true)
            let refused = !d.hybrid
            d.purpose = .shared
            t.check("Choosing 'Paid for someone' turns Hybrid Split off; it can't be turned on there; back to Shared it stays off",
                    off && refused && !d.usesHybrid && d.shares(totalMinor: 30000) == [10000, 10000, 10000],
                    expected: "off, refused, plain equal split", actual: "\(off) \(refused) \(describe(d.shares(totalMinor: 30000)))")
        }

        // Save → reload round trip
        do {
            let d = example()
            let expense = Expense(amount: 200, merchant: "Steamboat"); ctx.insert(expense)
            let saved = d.apply(to: expense, in: ctx); try? ctx.save()
            let rows = expense.shares.sorted { $0.sortIndex < $1.sortIndex }
            let canonical = #"{"type":"hybrid","version":1,"groups":[{"amountMinor":10000,"members":[1,2]}],"individuals":[{"participant":2,"amountMinor":2000}],"remaining":[0,1,2]}"#
            let fetched = (try? ctx.fetch(FetchDescriptor<Expense>()))?.first { $0.id == expense.id }
            let back = fetched.flatMap { SplitDraft(expense: $0) }
            let names: (Set<UUID>) -> [String] = { ids in back?.participants.filter { ids.contains($0.id) }.map { $0.isMe ? "Me" : $0.name } ?? [] }
            let groupBack = back?.hybridGroups.first
            let individualBack = back?.hybridIndividuals.first
            t.check("Saved as Custom Amount (amount = entered = final, sortIndex = position) + the canonical rule; reload restores Hybrid Split, RM 100.00 for Riad + Bijoy, Bijoy RM 20.00, remaining You + Riad + Bijoy",
                    saved && expense.splitMethod == .amounts && rows.map(\.amountMinor) == [2667, 7667, 9666] &&
                    rows.map(\.enteredMinor) == [2667, 7667, 9666] && rows.map(\.parts) == [nil, nil, nil] && rows.map(\.sortIndex) == [0, 1, 2] &&
                    expense.splitRule == canonical && back?.usesHybrid == true && back?.purpose == .shared &&
                    back?.hybridGroups.count == 1 && groupBack?.amountText == "100.00" && names(groupBack?.memberIDs ?? []) == ["Riad", "Bijoy"] &&
                    back?.hybridIndividuals.count == 1 && individualBack?.amountText == "20.00" &&
                    names(Set([individualBack?.participantID].compactMap { $0 })) == ["Bijoy"] &&
                    names(back?.remainderIDs ?? []) == ["Me", "Riad", "Bijoy"] && back?.shares(totalMinor: 20000) == [2667, 7667, 9666] &&
                    expense.sharesMatchAmount,
                    expected: canonical, actual: "\(expense.splitRule ?? "nil") \(rows.map(\.amountMinor)) back=\(back?.usesHybrid == true)")

            var off = back!
            off.setHybrid(false)
            t.check("Reloaded Hybrid Split turned off → Custom Amount with the same amounts; saving again clears the rule",
                    off.method == .amounts && off.shares(totalMinor: 20000) == [2667, 7667, 9666] &&
                    off.apply(to: fetched!, in: ctx) && fetched!.splitRule == nil,
                    expected: "[2667, 7667, 9666], rule nil", actual: "\(describe(off.shares(totalMinor: 20000))) \(fetched?.splitRule ?? "nil")")
        }

        // Fallback: a bad rule opens as the normal Custom Amount split
        do {
            func stored(_ rule: String?) -> SplitDraft? {
                let e = Expense(amount: 200, merchant: "Fallback"); ctx.insert(e)
                _ = example().apply(to: e, in: ctx)
                e.splitRule = rule
                return SplitDraft(expense: e)
            }
            let bad = ["{not json", #"{"type":"weighted","version":1,"groups":[],"individuals":[],"remaining":[0]}"#,
                       #"{"type":"hybrid","version":1,"groups":[{"amountMinor":10000,"members":[1,7]}],"individuals":[],"remaining":[0]}"#,
                       #"{"type":"hybrid","version":2,"groups":[],"individuals":[],"remaining":[0]}"#]
            let drafts = bad.map(stored)
            t.check("Bad JSON, unknown type, a position with no share, or an unknown version → opens as Custom Amount with the saved amounts",
                    drafts.allSatisfy { $0?.usesHybrid == false && $0?.method == .amounts && $0?.shares(totalMinor: 20000) == [2667, 7667, 9666] &&
                                        $0?.participants.map(\.amountText) == ["26.67", "76.67", "96.66"] },
                    expected: "4 × Custom Amount", actual: "\(drafts.map { "\($0?.usesHybrid ?? true)/\(describe($0?.shares(totalMinor: 20000)))" })")
        }

        // Me in no layer: RM 0.00, stays a shared split on reload (not 'Paid for someone')
        do {
            var d = SplitDraft(); d.add(riad); d.add(bijoy)
            d.setHybrid(true)
            let row = d.addIndividual(); d.setIndividualPerson(id(d, "Riad"), for: row); d.setIndividualAmountText("10", for: row)
            d.setInRemainder(false, participant: id(d, "Me"))
            let expense = Expense(amount: 50, merchant: "Gift"); ctx.insert(expense)
            let ok = d.apply(to: expense, in: ctx)
            let back = SplitDraft(expense: expense)
            t.check("Me in no layer → my share RM 0.00; reloads as a shared Hybrid Split",
                    ok && expense.shares.sorted { $0.sortIndex < $1.sortIndex }.map(\.amountMinor) == [0, 3000, 2000] &&
                    back?.purpose == .shared && back?.usesHybrid == true && back?.shares(totalMinor: 5000) == [0, 3000, 2000],
                    expected: "[0, 3000, 2000], shared hybrid", actual: "\(describe(back?.shares(totalMinor: 5000))) \(String(describing: back?.purpose))")
        }

        // Existing transactions load exactly as before
        do {
            let old = Expense(amount: 30, merchant: "Old custom"); ctx.insert(old)
            old.splitMethod = .amounts
            ctx.insert(ExpenseShare(expense: old, isMe: true, nameSnapshot: "Me", amountMinor: 1000, enteredMinor: 1000, sortIndex: 0))
            ctx.insert(ExpenseShare(expense: old, person: riad, nameSnapshot: "Riad", amountMinor: 2000, enteredMinor: 2000, sortIndex: 1))
            let parts = Expense(amount: 30, merchant: "Old parts"); ctx.insert(parts)
            parts.splitMethod = .parts
            ctx.insert(ExpenseShare(expense: parts, isMe: true, nameSnapshot: "Me", amountMinor: 1000, parts: 1, sortIndex: 0))
            ctx.insert(ExpenseShare(expense: parts, person: bijoy, nameSnapshot: "Bijoy", amountMinor: 2000, parts: 2, sortIndex: 1))
            try? ctx.save()
            let a = SplitDraft(expense: old), b = SplitDraft(expense: parts)
            t.check("Existing splits (no splitRule) load exactly as before: Custom 10/20 typed, Parts 1/2; Hybrid Split stays off",
                    old.splitRule == nil && a?.usesHybrid == false && a?.method == .amounts && a?.participants.map(\.amountText) == ["10.00", "20.00"] &&
                    a?.shares(totalMinor: 3000) == [1000, 2000] && b?.usesHybrid == false && b?.method == .parts &&
                    b?.participants.map(\.parts) == [1, 2] && b?.shares(totalMinor: 3000) == [1000, 2000],
                    expected: "unchanged", actual: "\(String(describing: a?.participants.map(\.amountText))) \(String(describing: b?.participants.map(\.parts)))")
        }

        // Backup JSON with and without splitRule
        do {
            let source = TestKit.context()
            let r = DebtSettlementTests.person("Riad", in: source), b = DebtSettlementTests.person("Bijoy", in: source)
            var d = SplitDraft(); d.add(r); d.add(b)
            d.setHybrid(true)
            let g = d.hybridGroups[0].id
            d.setGroupAmountText("100", for: g)
            d.setGroupMember(true, participant: id(d, "Riad"), group: g); d.setGroupMember(true, participant: id(d, "Bijoy"), group: g)
            let row = d.addIndividual(); d.setIndividualPerson(id(d, "Bijoy"), for: row); d.setIndividualAmountText("20", for: row)
            let hybridExpense = Expense(amount: 200, merchant: "Steamboat"); source.insert(hybridExpense)
            _ = d.apply(to: hybridExpense, in: source)
            var plain = SplitDraft(); plain.add(r)
            let plainExpense = Expense(amount: 10, merchant: "Teh"); source.insert(plainExpense)
            _ = plain.apply(to: plainExpense, in: source)
            try? source.save()

            let encoder = UserDataBackupService.makeEncoder(), decoder = UserDataBackupService.makeDecoder()
            let hybridJSON = (try? encoder.encode(UserDataBackupService.ExpenseDTO(from: hybridExpense))).map { String(decoding: $0, as: UTF8.self) } ?? ""
            let plainJSON = (try? encoder.encode(UserDataBackupService.ExpenseDTO(from: plainExpense))).map { String(decoding: $0, as: UTF8.self) } ?? ""
            // An older backup: the same expense without the key.
            var legacyObject = (try? JSONSerialization.jsonObject(with: Data(hybridJSON.utf8))) as? [String: Any] ?? [:]
            legacyObject.removeValue(forKey: "splitRule")
            let legacyData = (try? JSONSerialization.data(withJSONObject: legacyObject)) ?? Data()
            let legacy = try? decoder.decode(UserDataBackupService.ExpenseDTO.self, from: legacyData)
            t.check("Backup ExpenseDTO: splitRule written for a Hybrid Split, omitted for a normal split; an old backup without it decodes with nil and its shares",
                    hybridJSON.contains("\"splitRule\"") && hybridJSON.contains("hybrid") && !plainJSON.contains("splitRule") &&
                    legacy != nil && legacy?.splitRule == nil && legacy?.shares?.map(\.amountMinor) == [2667, 7667, 9666],
                    expected: "key only when set", actual: "hybrid=\(hybridJSON.contains("splitRule")) plain=\(plainJSON.contains("splitRule")) legacy=\(legacy != nil)")

            let payload = UserDataBackupService.makePayload(from: source)
            let data = try? encoder.encode(payload)
            let decoded = data.flatMap { try? decoder.decode(UserDataBackupService.BackupPayload.self, from: $0) }
            let target = TestKit.context()
            if let decoded { _ = UserDataBackupService.applyBackupPayload(decoded, into: target) }
            let restored = TestKit.fetch(Expense.self, in: target)
            let hybridBack = restored.first { $0.merchant == "Steamboat" }
            let draftBack = hybridBack.flatMap { SplitDraft(expense: $0) }
            let plainBack = restored.first { $0.merchant == "Teh" }
            t.check("Backup export → restore keeps the Hybrid Split (rule + exact shares) and the plain split stays plain",
                    hybridBack?.splitRule == hybridExpense.splitRule && draftBack?.usesHybrid == true &&
                    draftBack?.shares(totalMinor: 20000) == [2667, 7667, 9666] && plainBack?.splitRule == nil &&
                    plainBack.flatMap { SplitDraft(expense: $0) }?.usesHybrid == false,
                    expected: "restored", actual: "\(hybridBack?.splitRule ?? "nil") \(describe(draftBack?.shares(totalMinor: 20000)))")
        }

        // Amount change after saving
        do {
            let expense = Expense(amount: 200, merchant: "Changing"); ctx.insert(expense)
            _ = example().apply(to: expense, in: ctx)
            expense.amount = 230
            let ok = SplitDraft.recalculateAfterAmountChange(expense, in: ctx)
            let after = expense.shares.sorted { $0.sortIndex < $1.sortIndex }
            let ruleKept = expense.splitRule != nil && SplitDraft(expense: expense)?.usesHybrid == true
            expense.amount = 100                                   // RM120 fixed > RM100
            let tooSmall = SplitDraft.recalculateAfterAmountChange(expense, in: ctx)
            let kept = expense.shares.sorted { $0.sortIndex < $1.sortIndex }.map(\.amountMinor)
            t.check("Amount RM200→RM230: RM110 left by 3 → You 36.67, Riad 86.67, Bijoy 106.66 (rule kept). RM230→RM100: fixed RM120 > total → shares kept, reported as not matching",
                    ok && after.map(\.amountMinor) == [3667, 8667, 10666] && after.map(\.enteredMinor) == [3667, 8667, 10666] && ruleKept &&
                    !tooSmall && kept == [3667, 8667, 10666] && !expense.sharesMatchAmount,
                    expected: "[3667, 8667, 10666] then kept + not matching", actual: "\(after.map(\.amountMinor)) ok=\(ok) tooSmall=\(tooSmall) kept=\(kept)")
        }

        // Canonical JSON round trip + equality
        do {
            let rule = HybridRule(groups: [.init(amountMinor: 10000, members: [1, 2])], individuals: [.init(participant: 2, amountMinor: 2000)], remaining: [0, 1, 2])
            let parsed = HybridRule(json: rule.json)
            let a = example()
            var b = a; b.setGroupAmountText("101", for: b.hybridGroups[0].id)
            var c = a; c.setInRemainder(false, participant: id(c, "Riad"))
            var e = a; e.setHybrid(false)
            var same = a; same.setGroupAmountText("100", for: same.hybridGroups[0].id)
            t.check("Canonical rule JSON parses back to itself; draft equality covers the mode, every amount and member",
                    parsed == rule && a == same && a != b && a != c && a != e,
                    expected: "round trip, equal only when identical", actual: "\(parsed == rule) \(a == same) \(a != b) \(a != c) \(a != e)")
        }

        _ = labib
        return results
    }
}
