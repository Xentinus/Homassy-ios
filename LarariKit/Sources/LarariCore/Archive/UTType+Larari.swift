import UniformTypeIdentifiers

extension UTType {
    /// `.larari` archives. Declared in the app's Info.plist under UTExportedTypeDeclarations.
    /// Plain data, not `public.archive`: Files unpacks archives on tap instead of opening Larari.
    public static let larariArchive = UTType(exportedAs: "app.larari.archive", conformingTo: .data)
}
