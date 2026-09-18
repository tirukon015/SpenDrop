import SwiftUI
import SwiftData

public struct PayBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PayBookContact.name, order: .forward) private var allContacts: [PayBookContact]

    @State private var searchText: String = ""
    @State private var showingAddSheet: Bool = {
        ProcessInfo.processInfo.arguments.contains("--open-add")
    }()
    @State private var autoSelectedContact: PayBookContact?
    @State private var contactToDelete: PayBookContact?
    @State private var showingDeleteAlert: Bool = false

    public init() {}

    private var filteredContacts: [PayBookContact] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else {
            return allContacts
        }
        return allContacts.filter { contact in
            contact.name.lowercased().contains(term)
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if allContacts.isEmpty {
                    emptyState(
                        icon: "person.crop.rectangle.stack",
                        title: "No Payees Yet",
                        message: "Add your payment contacts to quickly view and copy their bank account details."
                    )
                } else if filteredContacts.isEmpty {
                    emptyState(
                        icon: "magnifyingglass",
                        title: "No matching payees",
                        message: "No payee found matching '\(searchText)'."
                    )
                } else {
                    List {
                        ForEach(filteredContacts) { contact in
                            NavigationLink(destination: PayBookDetailView(contact: contact)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(contact.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text(contact.displaySubtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    contactToDelete = contact
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
            .navigationTitle("PayBook")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search name...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingAddSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddPayBookContactView()
            }
            .navigationDestination(item: $autoSelectedContact) { contact in
                PayBookDetailView(contact: contact)
            }
            .task {
                if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "--open-detail"),
                   idx + 1 < ProcessInfo.processInfo.arguments.count {
                    let targetName = ProcessInfo.processInfo.arguments[idx + 1]
                    if let match = allContacts.first(where: { $0.name.lowercased() == targetName.lowercased() }) {
                        autoSelectedContact = match
                    }
                }
            }
            .alert("Delete Contact?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let contact = contactToDelete {
                        HapticFeedback.notification(.warning)
                        modelContext.delete(contact)
                        try? modelContext.save()
                    }
                    contactToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    contactToDelete = nil
                }
            } message: {
                if let contact = contactToDelete {
                    Text("Are you sure you want to delete \(contact.name)?")
                }
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

            if allContacts.isEmpty {
                Button(action: {
                    showingAddSheet = true
                }) {
                    Label("Add Payee", systemImage: "plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
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
