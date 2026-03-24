import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicType
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0
    @State private var showSSHImport = false

    private var isCompact: Bool { sizeClass == .compact }
    private var maxContentWidth: CGFloat { isCompact ? .infinity : 520 }
    private var iconSize: CGFloat { isCompact ? 64 : 80 }
    private var horizontalPad: CGFloat { isCompact ? 32 : 48 }

    var body: some View {
        TabView(selection: $page) {
            welcomePage.tag(0)
            hostsPage.tag(1)
            workspacesPage.tag(2)
            readyPage.tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .sheet(isPresented: $showSSHImport) {
            NavigationStack {
                SSHConfigImportView()
            }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        pageContainer {
            Image(systemName: "terminal.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Welcome to Roam")
                .font(isCompact ? .largeTitle.bold() : .system(size: 40, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            Text("A full-featured SSH client built for mobile development. Manage hosts, run terminals, browse files, and preview your work — all from your device.")
                .font(isCompact ? .body : .title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, horizontalPad)
        } action: {
            nextButton
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome. Page 1 of 4.")
    }

    // MARK: - Page 2: Add Hosts

    private var hostsPage: some View {
        pageContainer {
            Image(systemName: "server.rack")
                .font(.system(size: iconSize))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Connect to Hosts")
                .font(isCompact ? .largeTitle.bold() : .system(size: 40, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            Text("Add your SSH servers manually or import them from your existing ~/.ssh/config file in one tap.")
                .font(isCompact ? .body : .title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, horizontalPad)

            VStack(spacing: 12) {
                Button {
                    showSSHImport = true
                } label: {
                    Label("Import from SSH Config", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: isCompact ? .infinity : 320)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Opens a sheet to import hosts from your SSH configuration file.")

                Text("You can also add hosts later from the Hosts tab.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, horizontalPad)
        } action: {
            nextButton
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connect to Hosts. Page 2 of 4.")
    }

    // MARK: - Page 3: Workspaces & Helper

    private var workspacesPage: some View {
        pageContainer {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Workspaces & Helper")
                .font(isCompact ? .largeTitle.bold() : .system(size: 40, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: isCompact ? 16 : 20) {
                featureRow(
                    icon: "rectangle.split.3x1",
                    title: "Multi-pane Sessions",
                    detail: "Run terminals, preview web apps, and browse files side by side."
                )
                featureRow(
                    icon: "gearshape.2",
                    title: "Remote Helper",
                    detail: "A lightweight Rust binary that provides git status, log tailing, process detection, and more."
                )
                featureRow(
                    icon: "arrow.triangle.branch",
                    title: "Port Forwarding",
                    detail: "Forward remote ports to preview dev servers directly on your device."
                )
            }
            .frame(maxWidth: maxContentWidth, alignment: .leading)
            .padding(.horizontal, horizontalPad)
        } action: {
            nextButton
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspaces and Helper. Page 3 of 4.")
    }

    // MARK: - Page 4: Ready

    private var readyPage: some View {
        pageContainer {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(.Roam.alive)
                .accessibilityHidden(true)

            Text("You're All Set")
                .font(isCompact ? .largeTitle.bold() : .system(size: 40, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            Text("Start by adding a host, then create a workspace to begin your first session.")
                .font(isCompact ? .body : .title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, horizontalPad)
        } action: {
            Button {
                withAnimation { hasCompletedOnboarding = true }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: isCompact ? .infinity : 320)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, horizontalPad)
            .padding(.bottom, isCompact ? 32 : 48)
            .accessibilityHint("Finishes onboarding and opens the app.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("You're all set. Page 4 of 4.")
    }

    // MARK: - Layout Helpers

    /// Shared page layout: vertically centered content with a bottom-pinned action.
    private func pageContainer<Content: View, Action: View>(
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder action: @escaping () -> Action
    ) -> some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: isCompact ? 24 : 32) {
                    Spacer(minLength: isCompact ? 40 : geo.size.height * 0.12)

                    content()

                    Spacer(minLength: isCompact ? 20 : 40)

                    action()
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, isCompact ? 0 : 24)
    }

    private var nextButton: some View {
        Button {
            withAnimation { page += 1 }
        } label: {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: isCompact ? .infinity : 320)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, horizontalPad)
        .padding(.bottom, isCompact ? 32 : 48)
        .accessibilityHint("Moves to the next onboarding page.")
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: isCompact ? 14 : 18) {
            Image(systemName: icon)
                .font(isCompact ? .title2 : .title)
                .foregroundStyle(.tint)
                .frame(width: isCompact ? 32 : 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(isCompact ? .subheadline.bold() : .headline)
                Text(detail)
                    .font(isCompact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
