import SwiftUI
import KidTutorKit

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @State private var recentOnly = false

    var body: some View {
        let reports = AccuracyReport.compute(samples: model.samples, lastN: recentOnly ? 50 : nil)
        NavigationStack {
            List {
                Section {
                    Picker("Samples", selection: $recentOnly) {
                        Text("All tests").tag(false)
                        Text("Last 50").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if reports.isEmpty {
                    ContentUnavailableView(
                        "No tests yet",
                        systemImage: "chart.bar",
                        description: Text("Results appear here after you confirm answers in the Test tab.")
                    )
                }

                ForEach(reports, id: \.recognizerID) { report in
                    Section(model.recognizerName(report.recognizerID)) {
                        LabeledContent("Correct") {
                            Text("\(report.correct) of \(report.attempts) (\(report.rate.formatted(.percent.precision(.fractionLength(0)))))")
                                .monospacedDigit()
                        }
                        let hardest = report.characters.filter { $0.attempts >= 2 && $0.rate < 1 }.prefix(6)
                        if !hardest.isEmpty {
                            LabeledContent("Hardest characters") {
                                Text(hardest.map { "\($0.character) \($0.correct)/\($0.attempts)" }.joined(separator: "   "))
                                    .monospacedDigit()
                            }
                        }
                        ForEach(report.confusions.prefix(5), id: \.self) { confusion in
                            LabeledContent("Wrote “\(confusion.written)”, read \(confusion.read.isEmpty ? "nothing" : "“\(confusion.read)”")") {
                                Text("\(confusion.count)×")
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Section("Samples") {
                    NavigationLink {
                        SampleBrowser()
                    } label: {
                        LabeledContent("Browse and fix samples", value: "\(model.samples.count)")
                    }
                }
            }
            .navigationTitle("Results")
        }
    }
}

/// Every saved sample, grouped by its label. Long-press one to relabel or delete it.
struct SampleBrowser: View {
    @Environment(AppModel.self) private var model
    @State private var relabeling: InkSample?

    var body: some View {
        let groups = Dictionary(grouping: model.samples) { $0.confirmedLabel ?? "?" }
        let order = Alphabet.all.characters.filter { groups[$0] != nil } + (groups["?"] == nil ? [] : ["?"])
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(order, id: \.self) { label in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(label)  ·  \(groups[label]?.count ?? 0)")
                            .font(.title2.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                            ForEach(groups[label] ?? []) { sample in
                                InkThumbnail(ink: sample.ink)
                                    .overlay(alignment: .bottomTrailing) {
                                        if sample.source == .test {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(4)
                                        }
                                    }
                                    .contextMenu {
                                        Button("Relabel…", systemImage: "character.cursor.ibeam") { relabeling = sample }
                                        Button("Delete", systemImage: "trash", role: .destructive) { model.delete(sample.id) }
                                    }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Samples")
        .sheet(item: $relabeling) { sample in
            CharacterPicker(title: "Relabel sample") { label in
                model.relabel(sample.id, as: label)
                relabeling = nil
            }
        }
    }
}
