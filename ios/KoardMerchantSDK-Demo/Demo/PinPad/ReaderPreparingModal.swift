import SwiftUI

/// Fullscreen modal that takes over the moment the user tries to charge
/// before the reader is ready. Watches `ReaderStateManager.state` and
/// `progress`, shows a real progress bar, and auto-fires the pending sale
/// when the reader transitions to `.ready` (or progress reaches >= 99%).
///
/// The previous behavior — a tiny red text line under the pin pad — was
/// too easy to miss. This modal makes it obvious that the system is doing
/// something and gives the user a Retry button if it stalls.
struct ReaderPreparingModal: View {
    let readerState: ReaderStateManager
    /// Called when the reader transitions to ready while this modal is
    /// presented. The parent re-runs the pending sale.
    let onReady: () -> Void
    /// Called when the user manually dismisses (cancel button).
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hasTriggered = false

    var body: some View {
        ZStack {
            KoardBackgroundView()

            VStack(spacing: 28) {
                Spacer()

                statusGraphic
                    .frame(height: 80)

                VStack(spacing: 8) {
                    Text(headline)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(subhead)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                progressBlock
                    .padding(.horizontal, 32)

                if !readerState.lastEventDescription.isEmpty {
                    Text("Last reader event: \(readerState.lastEventDescription)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                actions
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
        .onChange(of: readerState.state) { _, newState in
            // Once the reader flips to `.ready` while this modal is up,
            // auto-fire the pending sale and let the parent dismiss us.
            if case .ready = newState, !hasTriggered {
                hasTriggered = true
                onReady()
            }
        }
        .onChange(of: readerState.progress) { _, newProgress in
            // SDK can announce readyForTap before our prepare() task
            // resumes; if progress jumps to 99+% but state is still
            // .preparing, treat that as good-enough.
            if newProgress >= 99, !hasTriggered, readerState.state.isPreparing {
                hasTriggered = true
                onReady()
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var statusGraphic: some View {
        switch readerState.state {
        case .preparing, .idle:
            ZStack {
                Circle()
                    .stroke(Color.koardGreen.opacity(0.18), lineWidth: 6)
                    .frame(width: 76, height: 76)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(100, readerState.progress))) / 100)
                    .stroke(Color.koardGreen, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 76, height: 76)
                    .animation(.easeOut(duration: 0.3), value: readerState.progress)
                Image(systemName: "wave.3.right")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.koardGreen)
            }
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.koardGreen)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
        case .unsupported:
            Image(systemName: "iphone.slash")
                .font(.system(size: 56))
                .foregroundStyle(.red.opacity(0.8))
        }
    }

    private var headline: String {
        switch readerState.state {
        case .preparing: return "Preparing card reader"
        case .idle: return "Starting card reader"
        case .ready: return "Reader ready"
        case .failed: return "Reader unavailable"
        case .unsupported: return "Tap to Pay not supported"
        }
    }

    private var subhead: String {
        switch readerState.state {
        case .preparing, .idle:
            return "Apple is initializing the secure session. Your sale will start automatically as soon as the reader is ready."
        case .ready:
            return "Hand the device to the customer to tap."
        case let .failed(message):
            return message
        case .unsupported:
            return "This device can't accept tap-to-pay sales. Use another iPhone with Apple Tap to Pay support."
        }
    }

    @ViewBuilder
    private var progressBlock: some View {
        if readerState.state.isPreparing || readerState.state == .idle {
            VStack(spacing: 6) {
                ProgressView(value: Double(readerState.progress), total: 100)
                    .progressViewStyle(.linear)
                    .tint(.koardGreen)
                HStack {
                    Text("\(readerState.progress)%")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Auto-runs sale when ready")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch readerState.state {
        case .failed:
            VStack(spacing: 10) {
                Button {
                    readerState.ensureReady(force: true)
                    hasTriggered = false
                } label: {
                    Text("Retry")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.koardGreen)
                        )
                }
                Button("Cancel", action: onDismiss)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .unsupported:
            Button("Close", action: onDismiss)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.red)
                )
        case .preparing, .idle, .ready:
            Button("Cancel", action: onDismiss)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let service = MockKoardMerchantService.environment
    let mgr = ReaderStateManager(koardMerchantService: service)
    return ReaderPreparingModal(
        readerState: mgr,
        onReady: {},
        onDismiss: {}
    )
}
