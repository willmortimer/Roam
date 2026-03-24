import SwiftUI
import SwiftData

struct WorkspaceEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HostRecord.alias) private var hosts: [HostRecord]

    var existingWorkspace: WorkspaceRecord?

    // Step 1: Basics
    @State private var name = ""
    @State private var descriptionText = ""
    @State private var environment = "dev"
    @State private var selectedHostID: String?
    @State private var repoPath = ""

    // Step 2: tmux
    @State private var shell = "/bin/zsh"
    @State private var tmuxSessionName = ""
    @State private var panes: [PaneDefinition] = []

    // Step 3: Optional
    @State private var preferredAgentCommand = ""
    @State private var forwards: [ForwardDefinition] = []
    @State private var autoDetectPreviews = true
    @State private var notes = ""
    @State private var tags = ""

    @State private var currentStep = 0
    private let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)

            TabView(selection: $currentStep) {
                step1Basics.tag(0)
                step2Tmux.tag(1)
                step3Optional.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: currentStep)
        }
        .navigationTitle(existingWorkspace == nil ? "New Workspace" : "Edit Workspace")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if currentStep < stepCount - 1 {
                    Button("Next") { currentStep += 1 }
                        .disabled(!canAdvanceFromCurrentStep)
                } else {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .bold()
                }
            }
        }
        .onAppear { loadExisting() }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: Spacing.lg) {
            ForEach(0..<stepCount, id: \.self) { step in
                VStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(stepDotColor(for: step))
                        .frame(width: 10, height: 10)
                        .scaleEffect(step == currentStep ? 1.3 : 1.0)
                        .animation(.spring(duration: 0.3), value: currentStep)

                    Text(stepLabel(for: step))
                        .font(.caption2)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                }
                .onTapGesture {
                    if step < currentStep || (step == currentStep + 1 && canAdvanceFromCurrentStep) {
                        currentStep = step
                    }
                }
            }
        }
    }

    private func stepDotColor(for step: Int) -> Color {
        if step < currentStep { return .Roam.alive }
        if step == currentStep { return .accentColor }
        return .Roam.dormant
    }

    private func stepLabel(for step: Int) -> String {
        switch step {
        case 0: "Basics"
        case 1: "Terminal"
        case 2: "Extras"
        default: ""
        }
    }

    // MARK: - Step 1: Basics

    private var step1Basics: some View {
        Form {
            Section {
                TextField("Workspace Name", text: $name)
                TextField("Short description (optional)", text: $descriptionText)
            } header: {
                Text("Workspace")
            } footer: {
                Text("Give this workspace a recognizable name. The description appears in the workspace list.")
            }

            Section {
                Picker("Host", selection: $selectedHostID) {
                    Text("Select a host").tag(nil as String?)
                    ForEach(hosts, id: \.id) { host in
                        Text("\(host.alias) (\(host.hostname))").tag(host.id as String?)
                    }
                }

                if hosts.isEmpty {
                    Label("Add a host first in the Hosts tab.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("The SSH host this workspace connects to.")
            }

            Section {
                TextField("e.g. ~/projects/my-app", text: $repoPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Repository Path")
            } footer: {
                Text("Absolute path to your project directory on the remote host. Leave blank to use the home directory.")
            }

            Section {
                Picker("Environment", selection: $environment) {
                    Text("Dev").tag("dev")
                    Text("Staging").tag("staging")
                    Text("Production").tag("prod")
                }
            } footer: {
                Text("Labels this workspace so you can distinguish dev, staging, and production at a glance.")
            }
        }
    }

    // MARK: - Step 2: Terminal / tmux

    private var step2Tmux: some View {
        Form {
            Section {
                TextField("e.g. my-project", text: $tmuxSessionName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("tmux Session Name")
            } footer: {
                Text("Roam attaches to this tmux session on resume, or creates it if it doesn't exist. Use a short, unique name like your project name.")
            }

            Section {
                TextField("e.g. /bin/zsh", text: $shell)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Shell")
            } footer: {
                Text("The default shell for your remote session. Common options: /bin/zsh, /bin/bash, /bin/fish")
            }

            Section {
                if panes.isEmpty {
                    Text("No panes defined yet. Roam will auto-detect roles from running processes when you resume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(panes.indices, id: \.self) { index in
                    HStack {
                        Picker("Role", selection: $panes[index].role) {
                            ForEach(PaneRole.allCases, id: \.self) { role in
                                Text(role.rawValue.capitalized).tag(role)
                            }
                        }
                        .labelsHidden()
                        TextField("Window name", text: $panes[index].window)
                            .textInputAutocapitalization(.never)
                    }
                }
                .onDelete { offsets in
                    panes.remove(atOffsets: offsets)
                }

                Button("Add Pane", systemImage: "plus.circle") {
                    panes.append(PaneDefinition(role: .shell, window: ""))
                }
            } header: {
                Text("Pane Roles (Optional)")
            } footer: {
                Text("Map tmux window names to roles so Roam can show the right lens. If you skip this, roles are auto-detected from running commands (e.g. pytest \u{2192} tests, npm run \u{2192} server).")
            }

            Section {
                paneRoleReference
            } header: {
                Text("Role Reference")
            }
        }
    }

    private var paneRoleReference: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            roleHint(role: "Shell", icon: "terminal", description: "General-purpose terminal")
            roleHint(role: "Agent", icon: "cpu", description: "AI coding agent (Codex, Claude, etc.)")
            roleHint(role: "Tests", icon: "checkmark.circle", description: "Test runner output")
            roleHint(role: "Server", icon: "server.rack", description: "Dev server (npm, flask, etc.)")
            roleHint(role: "Logs", icon: "doc.text", description: "Log tail or journalctl")
            roleHint(role: "DB", icon: "cylinder", description: "Database shell (psql, mysql, etc.)")
            roleHint(role: "Scratch", icon: "note.text", description: "Scratch / temporary pane")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func roleHint(role: String, icon: String, description: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .frame(width: 16)
            Text("**\(role)** \u{2013} \(description)")
        }
    }

    // MARK: - Step 3: Optional Extras

    private var step3Optional: some View {
        Form {
            Section {
                ForEach(forwards.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        TextField("Label (e.g. vite dev)", text: $forwards[index].name)
                        HStack {
                            Text("Port")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            TextField("3000", value: $forwards[index].remotePort, format: .number)
                                .keyboardType(.numberPad)
                                .frame(width: 80)
                            Spacer()
                            Toggle("Preview", isOn: $forwards[index].autoPreview)
                                .labelsHidden()
                            Text("Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    forwards.remove(atOffsets: offsets)
                }

                Button("Add Port Forward", systemImage: "plus.circle") {
                    forwards.append(ForwardDefinition(name: "", remotePort: 3000))
                }
            } header: {
                Text("Port Forwards")
            } footer: {
                Text("Forward remote ports to your device for previewing web apps. Toggle Preview to auto-open the forwarded port in the built-in browser. Ports are also auto-detected by the helper.")
            }

            Section {
                TextField("e.g. codex, claude, aider", text: $preferredAgentCommand)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("AI Agent (Optional)")
            } footer: {
                Text("If you use an AI coding agent, enter its command name. Roam will tag the pane running this command with the Agent role.")
            }

            Section {
                Toggle("Auto-detect preview servers", isOn: $autoDetectPreviews)
            } footer: {
                Text("When enabled, the helper scans for listening ports (e.g. vite, next dev) and offers to forward them automatically.")
            }

            Section {
                TextEditor(text: $notes)
                    .frame(minHeight: 50)
            } header: {
                Text("Notes (Optional)")
            }

            Section {
                TextField("e.g. backend, infra, ml", text: $tags)
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Tags")
            } footer: {
                Text("Comma-separated labels for filtering workspaces.")
            }
        }
    }

    // MARK: - Validation

    private var canAdvanceFromCurrentStep: Bool {
        switch currentStep {
        case 0: !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedHostID != nil
        case 1: !tmuxSessionName.trimmingCharacters(in: .whitespaces).isEmpty
        default: true
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedHostID != nil
            && !tmuxSessionName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Save

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

    // MARK: - Load Existing

    private func loadExisting() {
        guard let ws = existingWorkspace else { return }
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
