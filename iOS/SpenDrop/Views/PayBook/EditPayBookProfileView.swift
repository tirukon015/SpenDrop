import SwiftUI
import SwiftData
import PhotosUI

public struct EditPayBookProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable public var profile: PayBookProfile

    @State private var name: String
    @State private var notes: String
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoData: Data?

    public init(profile: PayBookProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _notes = State(initialValue: profile.notes ?? "")
        _photoData = State(initialValue: profile.photoData)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        !trimmedName.isEmpty
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            ZStack {
                                if let photoData, let uiImage = UIImage(data: photoData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 64, height: 64)
                                        .overlay(
                                            Text(profile.initials)
                                                .font(.system(size: 24, weight: .bold))
                                                .foregroundStyle(Color.blue)
                                        )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                    await MainActor.run {
                                        self.photoData = data
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Person Name *", text: $name)
                                .font(.headline)
                                .textContentType(.name)
                                .autocorrectionDisabled()

                            if photoData != nil {
                                Button("Remove Photo", role: .destructive) {
                                    photoData = nil
                                    selectedPhotoItem = nil
                                }
                                .font(.caption)
                            } else {
                                Text("Tap icon to change photo")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("EDIT PERSON PROFILE")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }

    private func saveChanges() {
        guard isValid else { return }

        profile.name = trimmedName
        profile.photoData = photoData
        profile.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        profile.updatedAt = Date()

        try? modelContext.save()
        HapticFeedback.notification(.success)
        dismiss()
    }
}
