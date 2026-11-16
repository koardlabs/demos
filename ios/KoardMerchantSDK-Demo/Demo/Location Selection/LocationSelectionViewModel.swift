import Foundation
import KoardSDK

@MainActor
@Observable
public final class LocationSelectionViewModel: Identifiable {
    @ObservationIgnored public let id: UUID = UUID()
    @ObservationIgnored private let koardMerchantService: KoardMerchantServiceable
    @ObservationIgnored public var delegate: Delegate

    public private(set) var showProgress: Bool = false
    public private(set) var locations: [Location] = []
    
    public struct Delegate {
        public var onLocationSelected: (Location) -> Void
    }

    init(
        koardMerchantService: KoardMerchantServiceable,
        delegate: Delegate
    ) {
        self.koardMerchantService = koardMerchantService
        self.delegate = delegate
    }
    
    public func fetchLocations() async {
        showProgress = true
        locations = []
        defer {
            showProgress = false
        }
        
        do {
            let refreshed = try await koardMerchantService.fetchLocations()
            try Task.checkCancellation()
            locations = refreshed
        } catch let koardError as KoardMerchantSDKError {
            print(koardError.errorDescription)
        } catch {
            print(error.localizedDescription)
        }

    }
    
    public func locationSelected(location: Location) {
        delegate.onLocationSelected(location)
    }
}

extension LocationSelectionViewModel: Hashable {
    public nonisolated static func == (lhs: LocationSelectionViewModel, rhs: LocationSelectionViewModel) -> Bool {
        lhs.id == rhs.id
    }

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
