import LarariCore
import SwiftUI

/// The product form's photo (P2-07b, 1A, the Contacts pattern): the 112 pt photo or a live monogram circle, with
/// "Fotó hozzáadása" / "Szerkesztés" under it. Picture and text are one menu, so every photo action stays behind the
/// picture (user request, 2026-09-24).
struct ProductFormPhotoHeader: View {
    let imageData: Data?
    let name: String
    /// nil when there is no camera.
    let takePhoto: (() -> Void)?
    let choosePhoto: () -> Void
    let editPhoto: () -> Void
    let removePhoto: () -> Void

    var body: some View {
        Menu {
            if let takePhoto {
                Button(action: takePhoto) { Label("product.form.takePhoto", systemImage: "camera") }
                    .accessibilityIdentifier("product.form.takePhoto")
            }
            Button(action: choosePhoto) { Label("product.form.choosePhoto", systemImage: "photo.on.rectangle") }
                .accessibilityIdentifier("product.form.choosePhoto")
            if imageData != nil {
                Button(action: editPhoto) { Label("product.form.editPhoto", systemImage: "crop.rotate") }
                    .accessibilityIdentifier("product.form.editPhoto")
                Divider()
                Button(role: .destructive, action: removePhoto) { Label("product.form.removePhoto", systemImage: "trash") }
                    .accessibilityIdentifier("product.form.removePhoto")
            }
        } label: {
            VStack(spacing: 8) {
                picture
                Text(imageData == nil ? "product.form.addPhoto" : "common.edit")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 8)
        }
        .accessibilityLabel(Text(imageData == nil ? "product.form.addPhoto" : "product.form.photo"))
        .accessibilityIdentifier("product.form.photo")
    }

    @ViewBuilder private var picture: some View {
        if imageData == nil, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 112, height: 112)
                .overlay {
                    Image(systemName: "camera").font(.system(size: 40)).foregroundStyle(.tertiary)
                }
                .accessibilityHidden(true)
        } else {
            ProductImageView(data: imageData, size: 112, name: name, style: .hero)
        }
    }
}
