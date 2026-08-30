import SwiftUI

/// One handle, and every service it belongs to.
///
/// The form used to be eight fields, one per service, and someone who uses the
/// same name everywhere had to type it eight times. That is not a form people
/// finish — it is a form they abandon, and the profile then looks empty
/// because the editor was tedious rather than because they had nothing to say.
///
/// This asks the question in the order it actually happens: here is my handle,
/// and here is where I use it. Signing up somewhere new later means opening
/// the handle you already have and ticking one more box, not starting again.
struct HandleEditor: View {
    /// The whole map, service key → handle. Edited in place.
    @Binding var handles: [String: String]
    /// The handle being edited, or nil for a new one.
    let existing: String?

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var selected: Set<String> = []
    @State private var addingService = false
    @State private var newService = ""
    @State private var loaded = false

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    /// Everything offerable: what the app knows, plus anything anyone named.
    private var services: [HandleService] {
        let custom = handles.keys
            .compactMap(HandleService.init(key:))
            .filter { if case .custom = $0 { true } else { false } }
        let extra = selected.compactMap(HandleService.init(key:))
            .filter { if case .custom = $0 { true } else { false } }
        var seen = Set<String>()
        return (HandleService.builtins + custom + extra).filter { seen.insert($0.key).inserted }
    }

    var body: some View {
        Form {
            Section {
                TextField("Your handle", text: $text)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } footer: {
                Text("The name itself. Where you use it comes next.")
            }

            Section {
                ForEach(services) { service in
                    row(service)
                }
                Button {
                    addingService = true
                } label: {
                    Label("Add a service", systemImage: "plus")
                }
            } header: {
                Text("Used on")
            } footer: {
                // Says the rule rather than letting someone discover it by
                // watching a service vanish from another handle.
                Text("A service belongs to one handle. Picking one that's already on another handle moves it here.")
            }

            if existing != nil {
                Section {
                    Button("Remove this handle", role: .destructive) {
                        for key in keys(of: existing ?? "") { handles[key] = nil }
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle(existing == nil ? "Add a handle" : "Edit handle")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { commit(); dismiss() }
                    .disabled(trimmed.isEmpty || selected.isEmpty)
            }
        }
        .alert("Add a service", isPresented: $addingService) {
            TextField("Apple Arcade", text: $newService)
            Button("Cancel", role: .cancel) { newService = "" }
            Button("Add") {
                let name = newService.trimmingCharacters(in: .whitespaces)
                newService = ""
                guard !name.isEmpty else { return }
                selected.insert(HandleService.custom(name).key)
            }
        } message: {
            Text("Anywhere else you play — Apple Arcade, a storefront, a forum.")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            text = existing ?? ""
            selected = Set(keys(of: existing ?? ""))
        }
    }

    private func row(_ service: HandleService) -> some View {
        // Who else has it, so "this will move" is visible before it happens
        // rather than discovered afterwards.
        let owner = handles[service.key]
        let takenByAnother = owner != nil && owner != existing
        let isOn = selected.contains(service.key)

        return Button {
            if isOn { selected.remove(service.key) } else { selected.insert(service.key) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.label).foregroundStyle(.primary)
                    if takenByAnother, let owner {
                        Text("Currently \(owner)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? AnyShapeStyle(LSTheme.accent)
                                          : AnyShapeStyle(.tertiary))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func keys(of handle: String) -> [String] {
        guard !handle.isEmpty else { return [] }
        return handles.filter { $0.value == handle }.map(\.key)
    }

    private func commit() {
        // Drop this handle's old assignments first, so unticking a service
        // actually releases it instead of leaving a stale key behind.
        for key in keys(of: existing ?? "") { handles[key] = nil }
        for key in selected { handles[key] = trimmed }
    }
}
