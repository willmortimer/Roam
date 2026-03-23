import SwiftUI

/// Parses test output from captured pane content and shows pass/fail summary.
/// Supports pytest, jest, cargo test, XCTest, and Go test formats.
struct TestLensView: View {
    let helperClient: (any HelperClientProtocol)?
    let tmuxSession: String
    let testPaneID: String?

    @State private var testResult: ParsedTestResult?
    @State private var rawOutput: String?
    @State private var isLoading = false
    @State private var showRawOutput = false
    @AppStorage("lastTestCommand") private var lastTestCommand = ""

    var body: some View {
        Group {
            if helperClient == nil || testPaneID == nil {
                ContentUnavailableView(
                    "No Test Pane",
                    systemImage: "checkmark.circle",
                    description: Text("Assign a pane with the 'tests' role to use the test lens.")
                )
            } else if isLoading {
                ProgressView("Capturing test output...")
            } else if let result = testResult {
                testResultView(result)
            } else {
                ContentUnavailableView(
                    "No Test Output",
                    systemImage: "doc.text",
                    description: Text("Capture test pane output to see results.")
                )
            }
        }
        .navigationTitle("Tests")
        .toolbar {
            if helperClient != nil && testPaneID != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Capture", systemImage: "arrow.clockwise") {
                        Task { await captureAndParse() }
                    }
                }
                if !lastTestCommand.isEmpty {
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Re-run", systemImage: "arrow.counterclockwise") {
                            Task { await rerunTests() }
                        }
                    }
                }
            }
            if rawOutput != nil {
                ToolbarItem(placement: .secondaryAction) {
                    Button("Raw Output") { showRawOutput.toggle() }
                }
            }
        }
        .sheet(isPresented: $showRawOutput) {
            NavigationStack {
                ScrollView {
                    Text(rawOutput ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle("Raw Output")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showRawOutput = false }
                    }
                }
            }
        }
    }

    private func testResultView(_ result: ParsedTestResult) -> some View {
        List {
            Section {
                HStack {
                    VStack {
                        Text("\(result.passed)")
                            .font(.title.bold().monospacedDigit())
                            .foregroundStyle(.iDev.alive)
                        Text("Passed")
                            .font(.caption2)
                    }
                    Spacer()
                    VStack {
                        Text("\(result.failed)")
                            .font(.title.bold().monospacedDigit())
                            .foregroundStyle(result.failed > 0 ? .iDev.danger : .secondary)
                        Text("Failed")
                            .font(.caption2)
                    }
                    Spacer()
                    VStack {
                        Text("\(result.total)")
                            .font(.title.bold().monospacedDigit())
                        Text("Total")
                            .font(.caption2)
                    }
                }
                .padding(.vertical, 4)
            }

            if !result.framework.isEmpty {
                Section {
                    Label(result.framework, systemImage: "gearshape.2")
                }
            }

            if !result.detectedCommand.isEmpty {
                Section("Last Command") {
                    Text(result.detectedCommand)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if !result.failedTests.isEmpty {
                Section("Failed Tests") {
                    ForEach(result.failedTests, id: \.self) { test in
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.iDev.danger)
                            Text(test)
                                .font(.system(.subheadline, design: .monospaced))
                        }
                    }
                }
            }
        }
    }

    private func captureAndParse() async {
        guard let helper = helperClient, let paneID = testPaneID else { return }
        isLoading = true

        do {
            let content = try await helper.capturePaneContent(session: tmuxSession, paneID: paneID, lines: 200)
            rawOutput = content
            let result = parseTestOutput(content)
            testResult = result
            if !result.detectedCommand.isEmpty {
                lastTestCommand = result.detectedCommand
            }
        } catch {
            // Non-fatal
        }
        isLoading = false
    }

    private func rerunTests() async {
        guard let helper = helperClient, let paneID = testPaneID, !lastTestCommand.isEmpty else { return }
        do {
            try await helper.sendKeys(session: tmuxSession, paneID: paneID, keys: lastTestCommand + " Enter")
        } catch {
            // Non-fatal
        }
    }

    // MARK: - Test Output Parser

    private func parseTestOutput(_ output: String) -> ParsedTestResult {
        if let result = parsePytest(output) { return result }
        if let result = parseJest(output) { return result }
        if let result = parseCargoTest(output) { return result }
        if let result = parseXCTest(output) { return result }
        if let result = parseGoTest(output) { return result }
        return ParsedTestResult(framework: "", passed: 0, failed: 0, total: 0, failedTests: [], detectedCommand: "")
    }

    private func parsePytest(_ output: String) -> ParsedTestResult? {
        let passedRegex = /(\d+)\s+passed/
        let failedRegex = /(\d+)\s+failed/
        let failedTestRegex = /FAILED\s+(\S+)/
        let cmdRegex = /\$\s+(pytest\S*\s+.+)/

        guard let passedMatch = output.firstMatch(of: passedRegex) else { return nil }
        let passed = Int(passedMatch.1) ?? 0
        let failed = output.firstMatch(of: failedRegex).flatMap { Int($0.1) } ?? 0
        let failedTests = output.matches(of: failedTestRegex).map { String($0.1) }
        let cmd = output.firstMatch(of: cmdRegex).map { String($0.1) } ?? ""

        return ParsedTestResult(framework: "pytest", passed: passed, failed: failed, total: passed + failed, failedTests: failedTests, detectedCommand: cmd)
    }

    private func parseJest(_ output: String) -> ParsedTestResult? {
        let testsRegex = /Tests:\s+.*?(\d+)\s+passed/
        let failedRegex = /Tests:\s+.*?(\d+)\s+failed/
        let failedTestRegex = /✕\s+(.+)/
        let cmdRegex = /\$\s+((?:npx|yarn|npm)\s+.+jest.+)/

        guard let passedMatch = output.firstMatch(of: testsRegex) else { return nil }
        let passed = Int(passedMatch.1) ?? 0
        let failed = output.firstMatch(of: failedRegex).flatMap { Int($0.1) } ?? 0
        let failedTests = output.matches(of: failedTestRegex).map { String($0.1).trimmingCharacters(in: .whitespaces) }
        let cmd = output.firstMatch(of: cmdRegex).map { String($0.1) } ?? ""

        return ParsedTestResult(framework: "jest", passed: passed, failed: failed, total: passed + failed, failedTests: failedTests, detectedCommand: cmd)
    }

    private func parseCargoTest(_ output: String) -> ParsedTestResult? {
        let resultRegex = /test result:\s+\w+\.\s+(\d+)\s+passed;\s+(\d+)\s+failed/
        let failedTestRegex = /test\s+(\S+)\s+\.\.\.\s+FAILED/
        let cmdRegex = /\$\s+(cargo\s+test.+)/

        guard let resultMatch = output.firstMatch(of: resultRegex) else { return nil }
        let passed = Int(resultMatch.1) ?? 0
        let failed = Int(resultMatch.2) ?? 0
        let failedTests = output.matches(of: failedTestRegex).map { String($0.1) }
        let cmd = output.firstMatch(of: cmdRegex).map { String($0.1) } ?? ""

        return ParsedTestResult(framework: "cargo test", passed: passed, failed: failed, total: passed + failed, failedTests: failedTests, detectedCommand: cmd)
    }

    private func parseXCTest(_ output: String) -> ParsedTestResult? {
        // "Executed N tests, with M failures"
        let summaryRegex = /Executed\s+(\d+)\s+test(?:s)?,\s+with\s+(\d+)\s+failure/
        let failedTestRegex = /Test Case\s+'-\[(\S+)\s+(\S+)\]'\s+failed/
        let cmdRegex = /\$\s+(xcodebuild\s+test.+|swift\s+test.+)/

        guard let summaryMatch = output.firstMatch(of: summaryRegex) else { return nil }
        let total = Int(summaryMatch.1) ?? 0
        let failed = Int(summaryMatch.2) ?? 0
        let passed = total - failed
        let failedTests = output.matches(of: failedTestRegex).map { "\($0.1).\($0.2)" }
        let cmd = output.firstMatch(of: cmdRegex).map { String($0.1) } ?? ""

        return ParsedTestResult(framework: "XCTest", passed: passed, failed: failed, total: total, failedTests: failedTests, detectedCommand: cmd)
    }

    private func parseGoTest(_ output: String) -> ParsedTestResult? {
        // "ok  package  0.123s" or "FAIL  package  0.123s"
        let passRegex = /--- PASS:\s+(\S+)/
        let failRegex = /--- FAIL:\s+(\S+)/
        let cmdRegex = /\$\s+(go\s+test.+)/

        let passedTests = output.matches(of: passRegex).map { String($0.1) }
        let failedTests = output.matches(of: failRegex).map { String($0.1) }

        guard !passedTests.isEmpty || !failedTests.isEmpty else { return nil }

        let cmd = output.firstMatch(of: cmdRegex).map { String($0.1) } ?? ""
        return ParsedTestResult(
            framework: "go test",
            passed: passedTests.count,
            failed: failedTests.count,
            total: passedTests.count + failedTests.count,
            failedTests: failedTests,
            detectedCommand: cmd
        )
    }
}

// MARK: - Parsed Test Result

struct ParsedTestResult {
    var framework: String
    var passed: Int
    var failed: Int
    var total: Int
    var failedTests: [String]
    var detectedCommand: String
}
