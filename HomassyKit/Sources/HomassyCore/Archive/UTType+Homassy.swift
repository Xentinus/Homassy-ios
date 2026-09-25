import UniformTypeIdentifiers

extension UTType {
    /// `.homassy` archives. Declared in the app's Info.plist under UTExportedTypeDeclarations.
    /// Plain data, not `public.archive`: Files unpacks archives on tap instead of opening Homassy.
    public static let homassyArchive = UTType(exportedAs: "com.homassy.archive", conformingTo: .data)
}
