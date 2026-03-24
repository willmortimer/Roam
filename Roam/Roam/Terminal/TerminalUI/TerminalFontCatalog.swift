import CoreText
import SwiftUI
import UIKit

enum TerminalSettingsKeys {
    static let fontFamily = "terminal.fontFamily"
    static let fontSize = "terminal.fontSize"
}

enum TerminalFontFamily: String, CaseIterable, Identifiable {
    case system
    case jetBrainsMonoNerdFont
    case jetBrainsMonoNLNerdFont
    case jetBrainsMonoNerdFontMono
    case mesloLGMNerdFont
    case mesloLGMNerdFontMono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "System Monospace"
        case .jetBrainsMonoNerdFont:
            "JetBrains Mono Nerd Font"
        case .jetBrainsMonoNLNerdFont:
            "JetBrains Mono NL Nerd Font"
        case .jetBrainsMonoNerdFontMono:
            "JetBrains Mono Nerd Font Mono"
        case .mesloLGMNerdFont:
            "Meslo LGM Nerd Font"
        case .mesloLGMNerdFontMono:
            "Meslo LGM Nerd Font Mono"
        }
    }

    var subtitle: String {
        switch self {
        case .system:
            "Uses the built-in iOS monospaced font."
        case .jetBrainsMonoNerdFont:
            "Uses bundled Nerd Font glyphs for prompts, icons, and dev tooling."
        case .jetBrainsMonoNLNerdFont:
            "No-ligature JetBrains Mono variant with bundled Nerd Font glyphs."
        case .jetBrainsMonoNerdFontMono:
            "Strict mono-cell JetBrains Mono variant with bundled Nerd Font glyphs."
        case .mesloLGMNerdFont:
            "Meslo LGM with bundled Nerd Font glyphs."
        case .mesloLGMNerdFontMono:
            "Meslo LGM mono-cell variant with bundled Nerd Font glyphs."
        }
    }
}

struct TerminalFontFaces {
    let normal: UIFont
    let bold: UIFont
    let italic: UIFont
    let boldItalic: UIFont
}

enum TerminalFontCatalog {
    private struct FaceSpec {
        let fontNames: [String]
        let fileBaseNames: [String]
    }

    private struct FaceCandidates {
        let normal: FaceSpec
        let bold: FaceSpec
        let italic: FaceSpec
        let boldItalic: FaceSpec

        var allFontNames: [String] {
            normal.fontNames + bold.fontNames + italic.fontNames + boldItalic.fontNames
        }

        var allFileBaseNames: [String] {
            normal.fileBaseNames + bold.fileBaseNames + italic.fileBaseNames + boldItalic.fileBaseNames
        }

        var requiredFileNames: [String] {
            allFileBaseNames.map { "\($0).ttf" }
        }
    }

    private static func face(fontNames: [String], fileBaseNames: [String]) -> FaceSpec {
        FaceSpec(fontNames: fontNames, fileBaseNames: fileBaseNames)
    }

    private static let jetBrainsMonoNerdFont = FaceCandidates(
        normal: face(
            fontNames: ["JetBrainsMonoNF-Regular", "JetBrainsMonoNerdFont-Regular"],
            fileBaseNames: ["JetBrainsMonoNerdFont-Regular"]
        ),
        bold: face(
            fontNames: ["JetBrainsMonoNF-Bold", "JetBrainsMonoNerdFont-Bold"],
            fileBaseNames: ["JetBrainsMonoNerdFont-Bold"]
        ),
        italic: face(
            fontNames: ["JetBrainsMonoNF-Italic", "JetBrainsMonoNerdFont-Italic"],
            fileBaseNames: ["JetBrainsMonoNerdFont-Italic"]
        ),
        boldItalic: face(
            fontNames: ["JetBrainsMonoNF-BoldItalic", "JetBrainsMonoNerdFont-BoldItalic"],
            fileBaseNames: ["JetBrainsMonoNerdFont-BoldItalic"]
        )
    )

    private static let jetBrainsMonoNLNerdFont = FaceCandidates(
        normal: face(
            fontNames: ["JetBrainsMonoNLNF-Regular", "JetBrainsMonoNLNerdFont-Regular"],
            fileBaseNames: ["JetBrainsMonoNLNerdFont-Regular"]
        ),
        bold: face(
            fontNames: ["JetBrainsMonoNLNF-Bold", "JetBrainsMonoNLNerdFont-Bold"],
            fileBaseNames: ["JetBrainsMonoNLNerdFont-Bold"]
        ),
        italic: face(
            fontNames: ["JetBrainsMonoNLNF-Italic", "JetBrainsMonoNLNerdFont-Italic"],
            fileBaseNames: ["JetBrainsMonoNLNerdFont-Italic"]
        ),
        boldItalic: face(
            fontNames: ["JetBrainsMonoNLNF-BoldItalic", "JetBrainsMonoNLNerdFont-BoldItalic"],
            fileBaseNames: ["JetBrainsMonoNLNerdFont-BoldItalic"]
        )
    )

    private static let jetBrainsMonoNerdFontMono = FaceCandidates(
        normal: face(
            fontNames: ["JetBrainsMonoNFM-Regular", "JetBrainsMonoNerdFontMono-Regular"],
            fileBaseNames: ["JetBrainsMonoNerdFontMono-Regular"]
        ),
        bold: face(
            fontNames: ["JetBrainsMonoNFM-Bold", "JetBrainsMonoNerdFontMono-Bold"],
            fileBaseNames: ["JetBrainsMonoNerdFontMono-Bold"]
        ),
        italic: face(
            fontNames: ["JetBrainsMonoNFM-Italic", "JetBrainsMonoNerdFontMono-Italic"],
            fileBaseNames: ["JetBrainsMonoNerdFontMono-Italic"]
        ),
        boldItalic: face(
            fontNames: ["JetBrainsMonoNFM-BoldItalic", "JetBrainsMonoNerdFontMono-BoldItalic"],
            fileBaseNames: ["JetBrainsMonoNerdFontMono-BoldItalic"]
        )
    )

    private static let mesloLGMNerdFont = FaceCandidates(
        normal: face(
            fontNames: ["MesloLGMNF-Regular", "MesloLGMNerdFont-Regular"],
            fileBaseNames: ["MesloLGMNerdFont-Regular"]
        ),
        bold: face(
            fontNames: ["MesloLGMNF-Bold", "MesloLGMNerdFont-Bold"],
            fileBaseNames: ["MesloLGMNerdFont-Bold"]
        ),
        italic: face(
            fontNames: ["MesloLGMNF-Italic", "MesloLGMNerdFont-Italic"],
            fileBaseNames: ["MesloLGMNerdFont-Italic"]
        ),
        boldItalic: face(
            fontNames: ["MesloLGMNF-BoldItalic", "MesloLGMNerdFont-BoldItalic"],
            fileBaseNames: ["MesloLGMNerdFont-BoldItalic"]
        )
    )

    private static let mesloLGMNerdFontMono = FaceCandidates(
        normal: face(
            fontNames: ["MesloLGMNFM-Regular", "MesloLGMNerdFontMono-Regular"],
            fileBaseNames: ["MesloLGMNerdFontMono-Regular"]
        ),
        bold: face(
            fontNames: ["MesloLGMNFM-Bold", "MesloLGMNerdFontMono-Bold"],
            fileBaseNames: ["MesloLGMNerdFontMono-Bold"]
        ),
        italic: face(
            fontNames: ["MesloLGMNFM-Italic", "MesloLGMNerdFontMono-Italic"],
            fileBaseNames: ["MesloLGMNerdFontMono-Italic"]
        ),
        boldItalic: face(
            fontNames: ["MesloLGMNFM-BoldItalic", "MesloLGMNerdFontMono-BoldItalic"],
            fileBaseNames: ["MesloLGMNerdFontMono-BoldItalic"]
        )
    )

    private static let bundledFamilies: [TerminalFontFamily: FaceCandidates] = [
        .jetBrainsMonoNerdFont: jetBrainsMonoNerdFont,
        .jetBrainsMonoNLNerdFont: jetBrainsMonoNLNerdFont,
        .jetBrainsMonoNerdFontMono: jetBrainsMonoNerdFontMono,
        .mesloLGMNerdFont: mesloLGMNerdFont,
        .mesloLGMNerdFontMono: mesloLGMNerdFontMono,
    ]

    private static let supportedFontExtensions = Set(["ttf", "otf"])
    private static var hasRegisteredBundledFonts = false

    static func faces(for family: TerminalFontFamily, size: CGFloat) -> TerminalFontFaces {
        registerBundledFontsIfNeeded()

        guard let candidates = bundledFamilies[family] else {
            return systemFaces(size: size)
        }

        return resolvedFaces(candidates: candidates, size: size) ?? systemFaces(size: size)
    }

    static func isAvailable(_ family: TerminalFontFamily) -> Bool {
        registerBundledFontsIfNeeded()

        guard let candidates = bundledFamilies[family] else {
            return true
        }

        return resolvedFaces(candidates: candidates, size: 13) != nil
    }

    static func requiredFiles(for family: TerminalFontFamily) -> [String] {
        bundledFamilies[family]?.requiredFileNames ?? []
    }

    static func registerBundledFontsIfNeeded() {
        guard !hasRegisteredBundledFonts else {
            return
        }

        hasRegisteredBundledFonts = true

        let candidateBaseNames = Set(bundledFamilies.values.flatMap(\.allFileBaseNames))
        guard
            !candidateBaseNames.isEmpty,
            let resourceURL = Bundle.main.resourceURL,
            let enumerator = FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        for case let fileURL as URL in enumerator {
            let fileExtension = fileURL.pathExtension.lowercased()
            guard supportedFontExtensions.contains(fileExtension) else {
                continue
            }

            let baseName = fileURL.deletingPathExtension().lastPathComponent
            guard candidateBaseNames.contains(baseName) else {
                continue
            }

            var registrationError: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, &registrationError)
        }
    }

    private static func systemFaces(size: CGFloat) -> TerminalFontFaces {
        let normal = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let bold = UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        let italic = derivedFont(from: normal, traits: [.traitItalic]) ?? normal
        let boldItalic = derivedFont(from: bold, traits: [.traitItalic, .traitBold])
            ?? derivedFont(from: normal, traits: [.traitItalic, .traitBold])
            ?? bold

        return TerminalFontFaces(
            normal: normal,
            bold: bold,
            italic: italic,
            boldItalic: boldItalic
        )
    }

    private static func resolvedFaces(candidates: FaceCandidates, size: CGFloat) -> TerminalFontFaces? {
        guard
            let normal = firstFont(for: candidates.normal, size: size),
            let bold = firstFont(for: candidates.bold, size: size),
            let italic = firstFont(for: candidates.italic, size: size),
            let boldItalic = firstFont(for: candidates.boldItalic, size: size)
        else {
            return nil
        }

        return TerminalFontFaces(
            normal: normal,
            bold: bold,
            italic: italic,
            boldItalic: boldItalic
        )
    }

    private static func firstFont(for face: FaceSpec, size: CGFloat) -> UIFont? {
        for name in face.fontNames {
            if let font = UIFont(name: name, size: size) {
                return font
            }
        }
        return nil
    }

    private static func derivedFont(
        from base: UIFont,
        traits: UIFontDescriptor.SymbolicTraits
    ) -> UIFont? {
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else {
            return nil
        }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}
