import SwiftUI

// MARK: - FocusLiftPickerView
//
// "Which lifts do you most want to add weight to?" as a PICKER. Owner
// 2026-08-27: "a drop down of some very common compound movements with
// an option at the bottom to select any from the catalog. Should also be
// able to specify multiple lifts."
//
// The curated list is resolved against the LOADED catalog by exact name,
// with fallbacks in order — an entry that matches nothing hides itself
// rather than offering a lift the generator cannot place. (The fail-open
// resolver that adopted the first search hit is this repo's recorded
// defect; this list fails closed.) The catalog door at the bottom opens
// a searchable sheet over every non-alias row, compounds first.
//
// Values are exercise ids (uuidString), so ConsultAnswers resolves them
// by id and the generator can make each one lead a day.
struct FocusLiftPickerView: View {
    let catalog: [Exercise]
    @Binding var selection: Set<String>

    @Environment(\.gsTheme) private var theme
    @State private var browsing = false

    /// Label → catalog names to try, in order. Names measured against the
    /// library 2026-08-27; the first that exists wins.
    static let curated: [(label: String, names: [String])] = [
        ("Bench press",        ["Bench Press", "Barbell Bench Press - Medium Grip"]),
        ("Back squat",         ["Back Squat", "Barbell Squat"]),
        ("Deadlift",           ["Barbell Deadlift", "Deadlift"]),
        ("Overhead press",     ["Overhead Press", "Standing Military Press"]),
        ("Barbell row",        ["Barbell Row"]),
        ("Pull-up",            ["Pull-Up", "Weighted Pull-Up"]),
        ("Chin-up",            ["Chin-Up"]),
        ("Front squat",        ["Front Squat"]),
        ("Romanian deadlift",  ["Romanian Deadlift"]),
        ("Incline bench",      ["Incline Bench Press", "Barbell Incline Bench Press - Medium Grip"]),
        ("Hip thrust",         ["Barbell Hip Thrust"]),
        ("Dip",                ["Chest Dip"]),
        ("Sumo deadlift",      ["Sumo Deadlift"]),
        ("Trap bar deadlift",  ["Trap Bar Deadlift"]),
        ("Leg press",          ["Leg Press"]),
    ]

    /// The curated entries that exist in this catalog, resolved.
    private var resolved: [(label: String, exercise: Exercise)] {
        let byName = Dictionary(catalog.filter { $0.aliasOf == nil }
                                    .map { ($0.name.lowercased(), $0) },
                                uniquingKeysWith: { first, _ in first })
        return Self.curated.compactMap { entry in
            for name in entry.names {
                if let ex = byName[name.lowercased()] { return (entry.label, ex) }
            }
            return nil
        }
    }

    /// Lifts picked from the catalog sheet that are not on the curated
    /// list — shown above the door so a pick never vanishes.
    private var extras: [Exercise] {
        let curatedIDs = Set(resolved.map(\.exercise.id.uuidString))
        return catalog.filter { selection.contains($0.id.uuidString)
                                && !curatedIDs.contains($0.id.uuidString) }
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(resolved, id: \.exercise.id) { entry in
                chip(entry.exercise, label: entry.label)
            }
            ForEach(extras) { exercise in
                chip(exercise, label: exercise.name)
            }
            Button { browsing = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .bold))
                    Text("ANY LIFT FROM THE CATALOG")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .tracking(0.8)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.gs3DCardStyle(cornerRadius: 15))
        }
        .sheet(isPresented: $browsing) {
            CatalogLiftSheet(catalog: catalog, selection: $selection)
        }
    }

    private func chip(_ exercise: Exercise, label: String) -> some View {
        let picked = selection.contains(exercise.id.uuidString)
        return Button {
            if picked { selection.remove(exercise.id.uuidString) }
            else { selection.insert(exercise.id.uuidString) }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label.uppercased())
                        .font(GSFont.bold(15, relativeTo: .headline))
                        .tracking(0.3)
                        .foregroundStyle(picked ? theme.bg : theme.text)
                    Text(ConsultVocabulary.display(exercise.primaryMuscle))
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(picked ? theme.bg.opacity(0.75) : theme.neutral700)
                }
                Spacer(minLength: 0)
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(GSFont.bold(16, relativeTo: .headline))
                    .foregroundStyle(picked ? theme.bg : theme.neutral700)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: 15,
                                    face: picked ? theme.accent : nil))
    }
}

// MARK: - CatalogLiftSheet
//
// The "any from the catalog" door: search over every non-alias row,
// compounds listed first because that is what "add weight to" means for
// almost everyone. Tapping toggles; the selection is shared with the
// picker behind it, so what is picked here shows there.
struct CatalogLiftSheet: View {
    let catalog: [Exercise]
    @Binding var selection: Set<String>

    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [Exercise] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = catalog.filter { ex in
            ex.aliasOf == nil
                && (query.isEmpty || ex.name.localizedCaseInsensitiveContains(query))
        }
        // Compounds first, then by name — stable, no scoring.
        return rows.sorted {
            let a = $0.category == "compound" ? 0 : 1
            let b = $1.category == "compound" ? 0 : 1
            return a != b ? a < b : $0.name < $1.name
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.neutral500)
                TextField("Search the catalog", text: $searchText)
                    .font(GSFont.body(15, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.neutral500)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gs3DCard(cornerRadius: 14)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filtered.prefix(150)) { exercise in
                        row(exercise)
                    }
                    if filtered.isEmpty {
                        Text("Nothing in the library matches that.")
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(theme.neutral700)
                            .padding(.top, 12)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Button { dismiss() } label: {
                Text(selection.isEmpty ? "DONE" : "DONE \u{2014} \(selection.count) PICKED")
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .tracking(0.9)
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(GS3DButtonStyle(face: theme.accent, cornerRadius: 14))
        }
        .padding(16)
        .background(theme.bg)
        .presentationDetents([.large])
    }

    private func row(_ exercise: Exercise) -> some View {
        let picked = selection.contains(exercise.id.uuidString)
        return Button {
            if picked { selection.remove(exercise.id.uuidString) }
            else { selection.insert(exercise.id.uuidString) }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text("\(ConsultVocabulary.display(exercise.primaryMuscle)) \u{00B7} \(ConsultVocabulary.display(exercise.equipment))")
                        .font(GSFont.body(10, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(GSFont.bold(16, relativeTo: .headline))
                    .foregroundStyle(picked ? theme.accent : theme.neutral500)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
