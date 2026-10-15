import Foundation

/// UI languages. German is the source language: the German text is the key, see docs/uebersetzen.md.
enum Lang: String, CaseIterable {
    case en, de
}

enum Loc {
    /// "system", "en" or "de"; the store sets it from the settings.
    static var choice = "system"

    /// German when German comes before English in the preferred languages, otherwise English.
    static var system: Lang {
        let first = Locale.preferredLanguages.first { $0.hasPrefix("de") || $0.hasPrefix("en") }
        return first?.hasPrefix("de") == true ? .de : .en
    }

    static var lang: Lang { Lang(rawValue: choice) ?? system }

    /// The text for the current language. Unknown keys fall back to the German key.
    static func text(_ de: String, in lang: Lang? = nil) -> String {
        switch lang ?? self.lang {
        case .de: de
        case .en: en[de] ?? de
        }
    }

    /// Every key of the table, for the self-test.
    static var keys: [String] { Array(en.keys) }
}

/// Translates a German source text.
func L(_ de: String) -> String { Loc.text(de) }

/// Translates a format string, then fills it in (%@, %d, %.1f and so on).
func L(_ de: String, _ args: CVarArg...) -> String { String(format: Loc.text(de), arguments: args) }

extension Preset {
    /// Built-ins show their name in the current language, as long as the stored name is still the
    /// German original. Own presets and renamed built-ins show what is stored.
    var displayName: String {
        guard builtIn, let f = Preset.factory.first(where: { $0.id == id }), f.name == name else { return name }
        return L(name)
    }
}

extension ObjectCatalog {
    /// Names that the catalog gave an object ("Ringplanet", "Roter Riese (nah)") in the current language.
    /// Names the user typed stay as they are.
    static func displayName(_ name: String) -> String {
        if Loc.en[name] != nil { return L(name) }
        let near = " (nah)"
        if name.hasSuffix(near), Loc.en[String(name.dropLast(near.count))] != nil {
            return L(String(name.dropLast(near.count))) + L(near)
        }
        return name
    }
}
