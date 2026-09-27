import SwiftUI
import SwiftData

public struct ExpenseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable public var expense: Expense
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false

    public init(expense: Expense) {
        self.expense = expense
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // HERO CARD
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(expense.category.color.opacity(0.15))
                                .frame(width: 72, height: 72)
                            Image(systemName: expense.category.icon)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(expense.category.color)
                        }

                        Text(expense.formattedAmount)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(expense.merchant)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    // DETAILS SECTION
                    VStack(spacing: 0) {
                        detailRow(title: "Category", value: expense.category.rawValue, icon: expense.category.icon, iconColor: expense.category.color)
                        Divider().padding(.leading, 48)

                        detailRow(title: "Funding Account", value: expense.effectiveFundingAccount, icon: "building.columns.fill", iconColor: .blue)
                        Divider().padding(.leading, 48)

                        detailRow(title: "Payment Channel", value: expense.paymentChannel.displayName, icon: expense.paymentChannel.iconName, iconColor: expense.paymentChannel.tintColor)
                        Divider().padding(.leading, 48)

                        if expense.isReconciled {
                            detailRow(title: "Status", value: "Reconciled", icon: "checkmark.seal.fill", iconColor: .blue)
                            Divider().padding(.leading, 48)
                        }

                        detailRow(title: "Date", value: expense.date.formatted(date: .long, time: .omitted), icon: "calendar", iconColor: .blue)
                        Divider().padding(.leading, 48)

                        detailRow(title: "Time", value: expense.date.formatted(date: .omitted, time: .shortened), icon: "clock.fill", iconColor: .teal)
                        Divider().padding(.leading, 48)

                        detailRow(title: "Source", value: expense.sourceType.displayName, icon: expense.sourceType.icon, iconColor: .indigo)

                        if let ref = expense.transactionReference, !ref.isEmpty {
                            Divider().padding(.leading, 48)
                            detailRow(title: "Reference", value: ref, icon: "number", iconColor: .gray)
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // NOTES SECTION
                    if let notes = expense.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                                .padding(.horizontal, 4)

                            Text(notes)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    // ORIGINAL IMAGE (Section 19: when practical)
                    if let imagePath = expense.imageRelativePath,
                       let uiImage = ImageStorageService.shared.loadImage(relativePath: imagePath) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ORIGINAL RECEIPT / SCREENSHOT")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                                .padding(.horizontal, 4)

                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    // DELETE BUTTON
                    Button(role: .destructive, action: {
                        showingDeleteAlert = true
                    }) {
                        Label("Delete Expense", systemImage: "trash.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 10)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Expense Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showingEditSheet = true
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                EditExpenseView(expense: expense)
            }
            .alert("Delete Expense?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    HapticFeedback.notification(.warning)
                    modelContext.delete(expense)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this expense of \(expense.formattedAmount)?")
            }
        }
    }

    private func detailRow(title: String, value: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
