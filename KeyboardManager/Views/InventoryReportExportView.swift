import SwiftUI

struct InventoryReportExportView: View {
    var currentKind: InventoryItemKind
    var export: (InventoryReportOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var options = InventoryReportOptions()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Bestandsbericht exportieren", systemImage: "square.and.arrow.up")
                .font(.title2.weight(.semibold))

            Form {
                Section {
                    Picker("Format", selection: $options.format) {
                        ForEach(InventoryReportFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if options.format == .xlsx {
                        Text("Excel enthält eine Übersicht und je Bereich ein filterbares Tabellenblatt.")
                    } else {
                        Text("PDF enthält ein Deckblatt, wiederholte Tabellenköpfe und Seitenzahlen.")
                    }
                }

                Section {
                    Picker("Umfang", selection: $options.scope) {
                        Text(InventoryReportScope.all.title).tag(InventoryReportScope.all)
                        Text(currentKind.displayName).tag(InventoryReportScope.current)
                    }
                    Toggle("Aktuelle Filter anwenden", isOn: $options.appliesFilters)
                    if options.format == .pdf {
                        Toggle("Vorschaubilder einbetten", isOn: $options.includesImages)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(height: 228)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Weiter …") {
                    var finalOptions = options
                    if finalOptions.format == .xlsx {
                        finalOptions.includesImages = false
                    }
                    dismiss()
                    export(finalOptions)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
