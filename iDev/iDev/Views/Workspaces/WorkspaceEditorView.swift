import SwiftUI
import SwiftData

struct WorkspaceEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HostRecord.alias) private var hosts: [HostRecord]

    var existingWorkspace: WorkspaceRecord?

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var environment = "dev"
    @State private var selectedHostID: String?
    @State private var shell = "/bin/zsh"
    @State private var repoPath = ""
    @State private var tmuxSessionName = ""
    @State private var preferredAgentCommand = ""
    @State private var notes = ""
    @State private var tags = ""
    @State private var panes: [PaneDefinition] = [PaneDefinition(role: .shell, window: "main")]
    @State private var forwards: [ForwardDefinition] = []
    @State private var autoDetectPreviews = true

    var body: some View {
        Form {
            Section("Workspace") {
                TextField("Name", text: $name)
                TextField("Description", text: $descriptionText)
                Picker("Environment", selection: $environment) {
                    Text("Dev").tag("dev")
                    Text("Staging").tag("staging")
                    Text("Production").tag("prod")
                }
            }

            Section("Connection") {
                Picker("Host", selection: $selectedHostID) {
                    Text("Select a host").tag(nil as String?)
                    ForEach(hosts, id: \.id) { host in
                        Text("\(host.alias) (\(host.hostname))").tag(host.id as String?)
                    }
                }
                TextField("Shell", text: $shell)
                    .textInputAutocapitalization(.never)
                TextField("Repo Path", text: $repoPath)
                    .textInputAutocapitalization(.never)
            }

            Section("tmux") {
                TextField("Session Name", text: $tmuxSessionName)
                    .textInputAutocapitalization(.never)

                ForEach(panes.indices, id: \.self) { index in
                    HStack {
                        Picker("Role", selection: $panes[index].role) {
                            ForEach(PaneRole.allCases, id: \.self) { role in
                                Text(role.rawValue.capitalized).tag(role)
                            }
                        }
                        TextField("Window", text: $panes[index].window)
                            .textInputAutocapitalization(.never)
                    }
                }
                .onDelete { offsets in
                    panes.remove(atOffsets: offsets)
                }

                Button("Add Pane") {
                    panes.append(PaneDefinition(role: .shell, window: "main"))
                }
            }

            Section("Agent") {
                TextField("Agent Command (e.g. codex, claude)", text: $preferredAgentCommand)
                    .textInputAutocapitalization(.never)
            }

            Section("Port Forwards") {
                ForEach(forwards.indices, id: \.self) { index in
                    VStack(alignment: .leading) {
                        TextField("Name", text: $forwards[index].name)
                        HStack {
                            TextField("Remote Port", value: $forwards[index].remotePort, format: .number)
                                .keyboardType(.numberPad)
                            Toggle("Auto Preview", isOn: $forwards[index].autoPreview)
                        }
                    }
                }
                .onDelete { offsets in
                    forwards.remove(atOffsets: offsets)
                }

                Button("Add Forward") {
                    forwards.append(ForwardDefinition(name: "", remotePort: 3000))
                }
            }

            Section("Preview") {
                Toggle("Auto-detect previews", isOn: $autoDetectPreviews)
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 60)
            }

            Section("Tags") {
                TextField("Tags (comma separated)", text: $tags)
                    .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle(existingWorkspace == nil ? "New Workspace" : "Edit Workspace")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(name.isEmpty || selectedHostID == nil || tmuxSessionName.isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if let ws = existingWorkspace {
                name = ws.name
                descriptionText = ws.descriptionText
                environment = ws.environment
                selectedHostID = ws.hostReference
                shell = ws.shell
                repoPath = ws.repoPath
                tmuxSessionName = ws.tmuxSessionName
                preferredAgentCommand = ws.preferredAgentCommand ?? ""
                notes = ws.notes
                tags = ws.tags.joined(separator: ", ")
                panes = ws.tmuxPanes
                forwards = ws.savedForwards
                autoDetectPreviews = ws.previewRules.autoDetect
            }
        }
    }

    private func save() {
        let parsedTags = tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let ws = existingWorkspace {
            ws.name = name
            ws.descriptionText = descriptionText
            ws.environment = environment
            ws.hostReference = selectedHostID ?? ""
            ws.shell = shell
            ws.repoPath = repoPath
            ws.startupDir = repoPath
            ws.tmuxSessionName = tmuxSessionName
            ws.preferredAgentCommand = preferredAgentCommand.isEmpty ? nil : preferredAgentCommand
            ws.notes = notes
            ws.tags = parsedTags
            ws.tmuxPanes = panes
            ws.savedForwards = forwards
            ws.previewRules = PreviewRulesConfig(autoDetect: autoDetectPreviews, openInApp: true)
            ws.updatedAt = Date()
        } else {
            let ws = WorkspaceRecord(
                name: name,
                descriptionText: descriptionText,
                environment: environment,
                hostReference: selectedHostID ?? "",
                shell: shell,
                repoPath: repoPath,
                startupDir: repoPath,
                tmuxSessionName: tmuxSessionName,
                preferredAgentCommand: preferredAgentCommand.isEmpty ? nil : preferredAgentCommand,
                notes: notes,
                tags: parsedTags
            )
            ws.tmuxPanes = panes
            ws.savedForwards = forwards
            ws.previewRules = PreviewRulesConfig(autoDetect: autoDetectPreviews, openInApp: true)
            modelContext.insert(ws)
        }

        dismiss()
    }
}
