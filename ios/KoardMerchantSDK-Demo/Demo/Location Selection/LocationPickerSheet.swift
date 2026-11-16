import SwiftUI
import KoardSDK

/// Shared bottom-sheet location picker. Originally lived inside
/// `SettingsView` as a private struct; pulled out so the pin-pad header
/// can drive the same picker without duplicating the chrome.
///
/// Pure UI — the caller passes in:
///   * the list of locations and which one is selected
///   * a loading flag
///   * `onLoad` (async) to fetch on appear
///   * `onSelect` to commit a pick
///
/// No view model dependency, so this works equally well with the
/// `SettingsViewModel` and `PinPadViewModel` flavors that both own
/// these fields.
struct LocationPickerSheet: View {
    let selectedLocation: Location?
    let availableLocations: [Location]
    let isLoading: Bool
    let onLoad: () async -> Void
    let onSelect: (Location) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasFinishedRefresh = false

    var body: some View {
        NavigationStack {
            Group {
                if !hasFinishedRefresh || isLoading {
                    ProgressView("Loading locations…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableLocations.isEmpty {
                    ContentUnavailableView(
                        "No locations",
                        systemImage: "mappin.slash",
                        description: Text("Your account has no locations to choose from.")
                    )
                } else {
                    List(availableLocations, id: \.id) { location in
                        Button {
                            onSelect(location)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location.name)
                                        .foregroundStyle(.primary)
                                        .font(.body.weight(.semibold))
                                    Text("\(location.address.city), \(location.address.state)")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                Spacer()
                                if selectedLocation?.id == location.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.koardGreen)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .background(KoardBackgroundView())
        }
        .task {
            hasFinishedRefresh = false
            await onLoad()
            guard !Task.isCancelled else { return }
            hasFinishedRefresh = true
        }
        .onDisappear { hasFinishedRefresh = false }
    }
}
