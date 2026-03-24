import SwiftUI

struct TerminalSettingsView: View {
    @AppStorage(TerminalSettingsKeys.fontFamily) private var fontFamily: TerminalFontFamily = .system
    @AppStorage(TerminalSettingsKeys.fontSize) private var fontSize = 13.0

    private var previewFaces: TerminalFontFaces {
        TerminalFontCatalog.faces(for: fontFamily, size: CGFloat(fontSize))
    }

    private var previewFontName: String {
        previewFaces.normal.fontName
    }

    var body: some View {
        List {
            Section("Font") {
                Picker("Family", selection: $fontFamily) {
                    ForEach(TerminalFontFamily.allCases) { family in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(family.title)
                            Text(family.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(family)
                    }
                }

                Stepper(value: $fontSize, in: 11 ... 24, step: 1) {
                    LabeledContent("Size", value: "\(Int(fontSize)) pt")
                }

                if fontFamily != .system && !TerminalFontCatalog.isAvailable(fontFamily) {
                    Text("\(fontFamily.title) will activate automatically once the bundled regular, bold, italic, and bold-italic font files are present.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("$ ls -la")
                        .font(.custom(previewFontName, size: fontSize))
                    Text("dev    ~/src/Roam  󰆍  git:(main)")
                        .font(.custom(previewFontName, size: fontSize))
                    Text("❯ swift build && ssh dev-box")
                        .font(.custom(previewFontName, size: fontSize))
                    Text("emoji  😄  🚀  📦")
                        .font(.custom(previewFontName, size: fontSize))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Spacing.xs)
            }
        }
        .navigationTitle("Terminal")
    }
}
