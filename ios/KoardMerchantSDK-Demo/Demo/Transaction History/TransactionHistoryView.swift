import KoardSDK
import SwiftUI

struct TransactionHistoryView: View {
    @State private var viewModel: TransactionHistoryViewModel
    @State private var search = ""
    @State private var filter: ActivityFilter = .all

    private enum ActivityFilter: String, CaseIterable, Identifiable {
        case all = "All payments", authorized = "Authorizations", completed = "Completed"
        var id: String { rawValue }
    }

    init(viewModel: TransactionHistoryViewModel) { self.viewModel = viewModel }

    private var visibleTransactions: [KoardTransaction] {
        viewModel.transactions.filter { transaction in
            let matchesStatus: Bool
            switch filter {
            case .all: matchesStatus = true
            case .authorized: matchesStatus = transaction.status == .authorized
            case .completed: matchesStatus = transaction.status == .captured || transaction.status == .settled
            }
            return matchesStatus && (search.isEmpty
                || transaction.transactionId.localizedCaseInsensitiveContains(search)
                || transaction.card.localizedCaseInsensitiveContains(search)
                || transaction.cardBrand.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Payment activity").font(.system(size: 28, weight: .bold))
                        Text("Receipts, authorizations, and follow-up actions.")
                            .font(.subheadline).foregroundStyle(POSDesign.muted)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(POSDesign.muted)
                        TextField("Find card or transaction", text: $search)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    .padding(14).background(POSDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ActivityFilter.allCases) { option in
                                Button { filter = option } label: {
                                    Text(option.rawValue).font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14).frame(minHeight: 44)
                                        .foregroundStyle(filter == option ? Color.white : POSDesign.ink)
                                        .background(filter == option ? Color.koardGreen : POSDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(filter == option ? .isSelected : [])
                            }
                        }
                    }
                    if let error = viewModel.loadError {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error).foregroundStyle(.red).accessibilityIdentifier("history.error")
                            Button("Retry") { Task { await viewModel.retryLastLoad() } }
                                .buttonStyle(POSButtonStyle())
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(POSDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if viewModel.isFetchingTransactions && viewModel.transactions.isEmpty {
                        ProgressView("Loading payments…").frame(maxWidth: .infinity).padding(40)
                    } else if visibleTransactions.isEmpty && viewModel.loadError == nil {
                        ContentUnavailableView("No matching payments", systemImage: "receipt", description: Text("Refresh or choose another filter."))
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(visibleTransactions, id: \.transactionId) { transaction in
                                NavigationLink(value: transaction.transactionId) {
                                    TransactionRow(transaction: transaction)
                                }
                                .buttonStyle(.plain)
                                .onAppear { Task { await viewModel.loadMoreIfNeeded(currentItem: transaction) } }
                            }
                        }
                    }
                    if viewModel.isLoadingMore { ProgressView().frame(maxWidth: .infinity).padding() }
                    else if viewModel.hasMorePages {
                        Button("Load more payments") { Task { await viewModel.loadNextPage() } }
                            .buttonStyle(POSButtonStyle()).frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier(viewModel.hasFinishedLoading ? "history.loaded" : "history.loading")
            .foregroundStyle(POSDesign.ink)
            .background(POSDesign.background)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await viewModel.getTransactions() }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { transactionID in
                if let transaction = viewModel.transactions.first(where: { $0.transactionId == transactionID }) {
                    TransactionDetailsView(viewModel: .init(
                        koardMerchantService: viewModel.koardMerchantService,
                        transaction: transaction,
                        delegate: .init(onTransactionUpdate: { Task { await viewModel.getTransactions() } })
                    ))
                }
            }
            .task { await viewModel.getTransactions() }
            .tint(.koardGreen)
        }
    }
}

private struct TransactionRow: View {
    let transaction: KoardTransaction

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: transaction.status == .authorized ? "clock" : "creditcard")
                .font(.title3)
                .foregroundStyle(transaction.status.statusColor)
                .frame(width: 44, height: 44)
                .background(transaction.status.statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text([transaction.cardBrand, transaction.card].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(transaction.createdAtDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption).foregroundStyle(POSDesign.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(MoneyUtils.centsToStringWithCurrency(transaction.displayedTotalCents))
                    .font(.system(size: 19, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(transaction.status.displayName)
                    .font(.caption.weight(.medium)).foregroundStyle(transaction.status.statusColor)
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(POSDesign.muted)
        }
        .padding(16)
        .background(POSDesign.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(POSDesign.line, lineWidth: 1))
    }
}

#Preview { TransactionHistoryView(viewModel: .init(koardMerchantService: .mockMerchantService)) }
