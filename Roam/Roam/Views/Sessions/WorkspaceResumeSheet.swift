import SwiftUI

struct WorkspaceResumeSheet: View {
    @Environment(WorkspaceResumeOrchestrator.self) private var resumeOrchestrator

    let workspaceName: String
    let host: HostRecord

    private var isDismissable: Bool {
        switch resumeOrchestrator.phase {
        case .ready, .failed: true
        default: false
        }
    }

    var body: some View {
        Group {
            if let verification = resumeOrchestrator.hostKeyVerificationRequest {
                HostKeyVerificationSheet(
                    hostname: host.hostname,
                    port: host.port,
                    hostKey: verification.hostKey,
                    existingRecord: verification.existingRecord,
                    onDecision: { decision in
                        resumeOrchestrator.submitHostKeyDecision(decision)
                    }
                )
            } else if let helperInstallRequest = resumeOrchestrator.helperInstallRequest {
                HelperInstallSheet(
                    detectionResult: helperInstallRequest.detectionResult,
                    onInstall: {
                        resumeOrchestrator.submitHelperInstallDecision(.install)
                    },
                    onSkip: {
                        resumeOrchestrator.submitHelperInstallDecision(.skip)
                    }
                )
            } else if let resumePlanRequest = resumeOrchestrator.resumePlanRequest {
                ResumePlanSheet(
                    plan: resumePlanRequest.plan,
                    workspaceName: workspaceName,
                    onProceed: {
                        resumeOrchestrator.submitResumePlanDecision(.proceed)
                    },
                    onSkip: {
                        resumeOrchestrator.submitResumePlanDecision(.skipHelperFeatures)
                    }
                )
            } else {
                WorkspaceResumeProgressSheet(workspaceName: workspaceName)
            }
        }
        .interactiveDismissDisabled(!isDismissable)
    }
}
