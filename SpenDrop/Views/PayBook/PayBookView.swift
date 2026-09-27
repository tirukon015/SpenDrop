import SwiftUI
import SwiftData

public struct PayBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PayBookProfile.name, order: .forward) private var allProfiles: [PayBookProfile]

    @State private var searchText: String = ""
    @State private var showingAddProfileSheet: Bool = {
        ProcessInfo.processInfo.arguments.contains("--open-add")
    }()
    @State private var autoSelectedProfile: PayBookProfile?
    @State private var profileToDelete: PayBookProfile?
    @State private var showingDeleteAlert: Bool = false

    public init() {}

    private var filteredProfiles: [PayBookProfile] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else {
            return allProfiles
        }
        return allProfiles.filter { profile in
            if profile.name.lowercased().contains(term) {
                return true
            }
            // Also search child payment methods (provider, account, label)
            return profile.paymentMethods.contains { method in
                method.displayProvider.lowercased().contains(term) ||
                method.accountIdentifier.contains(term) ||
                (method.label?.lowercased().contains(term) == true)
            }
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if allProfiles.isEmpty {
                    emptyState(
                        icon: "person.crop.rectangle.stack",
                        title: "Your Paybook is empty",
                        message: "Save people and their payment details so you can quickly reuse them later."
                    )
                } else if filteredProfiles.isEmpty {
                    emptyState(
                        icon: "magnifyingglass",
                        title: "No matching profiles",
                        message: "No person or account found matching '\(searchText)'."
                    )
                } else {
                    List {
                        ForEach(filteredProfiles) { profile in
                            NavigationLink(destination: PayBookDetailView(profile: profile)) {
                                HStack(spacing: 14) {
                                    // Profile Avatar
                                    avatarView(profile: profile, size: 48)

                                    // Name and Methods
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        HStack(spacing: 6) {
                                            Text(profile.paymentMethodCountText)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)

                                            if !profile.paymentMethods.isEmpty {
                                                Text("•")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)

                                                Text(profile.providersSummary)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    profileToDelete = profile
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Paybook")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search people, banks, accounts...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingAddProfileSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .sheet(isPresented: $showingAddProfileSheet) {
                AddPayBookProfileView()
            }
            .navigationDestination(item: $autoSelectedProfile) { profile in
                PayBookDetailView(profile: profile)
            }
            .task {
                if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "--open-detail"),
                   idx + 1 < ProcessInfo.processInfo.arguments.count {
                    let targetName = ProcessInfo.processInfo.arguments[idx + 1]
                    if let match = allProfiles.first(where: { $0.name.lowercased() == targetName.lowercased() }) {
                        autoSelectedProfile = match
                    }
                }
            }
            .alert("Delete \(profileToDelete?.name ?? "Profile")?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let profile = profileToDelete {
                        HapticFeedback.notification(.warning)
                        modelContext.delete(profile)
                        try? modelContext.save()
                    }
                    profileToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    profileToDelete = nil
                }
            } message: {
                if let profile = profileToDelete {
                    Text("This will remove \(profile.name) and all saved payment methods under this profile.")
                }
            }
        }
    }

    private func avatarView(profile: PayBookProfile, size: CGFloat) -> some View {
        ZStack {
            if let photoData = profile.photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(profile.initials)
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundStyle(Color.blue)
                    )
            }
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if allProfiles.isEmpty {
                Button(action: {
                    showingAddProfileSheet = true
                }) {
                    Label("Add Person", systemImage: "plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
