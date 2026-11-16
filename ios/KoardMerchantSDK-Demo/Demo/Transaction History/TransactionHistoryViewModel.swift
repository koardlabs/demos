import Foundation
import KoardSDK

@MainActor
@Observable
public final class TransactionHistoryViewModel: Identifiable {
    public private(set) var isFetchingTransactions: Bool = false
    /// True while a *subsequent* page is being appended (distinct from the
    /// initial/refresh load so the view can show a bottom spinner instead of
    /// the full-screen one).
    public private(set) var isLoadingMore: Bool = false
    public private(set) var loadError: String?
    public private(set) var hasFinishedLoading = false
    @ObservationIgnored private var retryLoadsNextPage = false
    public private(set) var transactions: [KoardTransaction] = []
    /// Whether the server reported more pages beyond what we've loaded.
    public private(set) var hasMorePages: Bool = false

    /// Number of transactions requested per page.
    @ObservationIgnored private let pageSize = 50
    /// Offset to request for the *next* page. Advances by the number of rows
    /// actually returned so a short page can't desync the cursor.
    @ObservationIgnored private var nextOffset = 0

    @ObservationIgnored public let id: UUID = UUID()
    /// Exposed (not @ObservationIgnored) so the History list can hand it to
    /// the pushed Details page without a new dependency channel.
    public let koardMerchantService: KoardMerchantServiceable

    init(koardMerchantService: KoardMerchantServiceable) {
        self.koardMerchantService = koardMerchantService
    }

    /// Initial load / pull-to-refresh. Resets pagination back to the first page
    /// and replaces the list.
    public func getTransactions() async {
        // Also bail if a load-more is in flight: a refresh resets
        // transactions/nextOffset, and a still-awaiting loadNextPage() would
        // otherwise resume and append its now-stale page on top, desyncing the
        // pagination cursor.
        guard !isFetchingTransactions, !isLoadingMore else { return }
        loadError = nil
        isFetchingTransactions = true
        defer { isFetchingTransactions = false }

        do {
            let response = try await fetchPage(offset: 0)
            try Task.checkCancellation()
            transactions = response.transactions
            nextOffset = response.transactions.count
            hasMorePages = response.hasMorePages
            hasFinishedLoading = true
        } catch is CancellationError {
            return
        } catch {
            hasFinishedLoading = true
            loadError = "Payments couldn't be loaded. Try again."
            retryLoadsNextPage = false
            print("[TransactionHistoryViewModel] fetch failed: \(error)")
        }
    }

    /// Called as rows appear. When the row that's appearing is near the end of
    /// the currently-loaded list, fetch and append the next page.
    public func loadMoreIfNeeded(currentItem: KoardTransaction) async {
        // Trigger when we're within the last few rows of what's loaded.
        let thresholdIndex = transactions.index(transactions.endIndex, offsetBy: -5, limitedBy: transactions.startIndex) ?? transactions.startIndex
        guard let currentIndex = transactions.firstIndex(where: { $0.transactionId == currentItem.transactionId }),
              currentIndex >= thresholdIndex else {
            return
        }
        await loadNextPage()
    }

    /// Fetches the next page (using the running offset) and appends the new,
    /// not-already-present rows to the list.
    public func loadNextPage() async {
        guard hasMorePages, !isLoadingMore, !isFetchingTransactions else { return }
        loadError = nil
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await fetchPage(offset: nextOffset)
            try Task.checkCancellation()
            let existingIds = Set(transactions.map(\.transactionId))
            let newTransactions = response.transactions.filter { !existingIds.contains($0.transactionId) }
            transactions.append(contentsOf: newTransactions)
            nextOffset += response.transactions.count

            // Stop paging if the server says there's nothing more, OR if a page
            // came back with no genuinely-new rows. The latter guards against an
            // offset/de-dup desync (e.g. the window shifts because rows were
            // added mid-scroll) silently turning into an endless re-fetch of the
            // same page on every scroll-to-bottom.
            hasMorePages = response.hasMorePages && !(response.transactions.isEmpty || newTransactions.isEmpty)
        } catch is CancellationError {
            return
        } catch {
            loadError = "More payments couldn't be loaded. Try again."
            retryLoadsNextPage = true
            print("[TransactionHistoryViewModel] load-more failed: \(error)")
        }
    }

    public func retryLastLoad() async {
        if retryLoadsNextPage { await loadNextPage() }
        else { await getTransactions() }
    }

    private func fetchPage(offset: Int) async throws -> TransactionHistoryResponse {
        try await koardMerchantService.getTransactionHistory(
            startDate: Date().addingTimeInterval(-86400 * 180), // 180 days
            endDate: Date(),
            statuses: nil,
            types: nil,
            minAmount: nil,
            maxAmount: nil,
            limit: pageSize,
            offset: offset
        )
    }
}

extension TransactionHistoryViewModel: Hashable {
    public nonisolated static func == (lhs: TransactionHistoryViewModel, rhs: TransactionHistoryViewModel) -> Bool {
        lhs.id == rhs.id
    }

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
