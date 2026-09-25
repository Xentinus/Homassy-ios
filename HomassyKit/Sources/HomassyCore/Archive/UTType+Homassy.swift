import UniformTypeIdentifiers

extension UTType {
    /// `.homassy` archives. Declared in the app's Info.plist under UTExportedTypeDeclarations.
    public static let homassyArchive = UTType(exportedAs: "com.homassy.archive", conformingTo: .archive)
}
