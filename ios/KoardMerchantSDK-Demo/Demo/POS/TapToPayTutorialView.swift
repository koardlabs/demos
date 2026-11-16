import ProximityReader
import SwiftUI

/// Opens Apple's localized merchant education, including its own illustrations.
struct TapToPayTutorialView: View {
    @State private var showAppleGuide = false
    @State private var presentationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "wave.3.right.circle.fill").font(.system(size: 56)).foregroundStyle(.koardGreen)
            Text("Tap to Pay on iPhone").font(.title.weight(.bold))
            Text("Learn how to accept contactless cards, digital wallets, and PIN payments with Apple's step-by-step guide.")
                .foregroundStyle(POSDesign.muted)
            if #available(iOS 18.0, *) {
                Button { showAppleGuide = true } label: { Text("Open Apple tutorial").frame(maxWidth: .infinity) }
                    .buttonStyle(POSButtonStyle(prominent: true))
                    .accessibilityIdentifier("tutorial.apple.open")
            } else {
                Text("Apple's in-app tutorial requires iOS 18 or later.").font(.footnote).foregroundStyle(POSDesign.muted)
            }
            Spacer()
        }
        .padding(24)
        .background(POSDesign.background)
        .navigationTitle("Tap to Pay guide")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showAppleGuide) {
            if #available(iOS 18.0, *) {
                AppleTapToPayGuide(onFinish: { error in
                    showAppleGuide = false
                    presentationError = error
                })
                .ignoresSafeArea()
            }
        }
        .alert("Tutorial unavailable", isPresented: Binding(get: { presentationError != nil }, set: { if !$0 { presentationError = nil } })) {
            Button("OK") { presentationError = nil }
        } message: { Text(presentationError ?? "") }
    }
}

@available(iOS 18.0, *)
private struct AppleTapToPayGuide: UIViewControllerRepresentable {
    let onFinish: (String?) -> Void

    func makeUIViewController(context: Context) -> GuideController { GuideController(onFinish: onFinish) }
    func updateUIViewController(_ controller: GuideController, context: Context) {}

    final class GuideController: UIViewController {
        private let discovery = ProximityReaderDiscovery()
        private let onFinish: (String?) -> Void
        private var didPresent = false
        private var presentationTask: Task<Void, Never>?
        private let cancelButton = UIButton(type: .system)

        init(onFinish: @escaping (String?) -> Void) {
            self.onFinish = onFinish
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(spinner)
            NSLayoutConstraint.activate([spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
            spinner.startAnimating()
            cancelButton.setTitle("Cancel", for: .normal)
            cancelButton.accessibilityIdentifier = "tutorial.apple.cancel"
            cancelButton.translatesAutoresizingMaskIntoConstraints = false
            cancelButton.addTarget(self, action: #selector(cancelLoading), for: .touchUpInside)
            view.addSubview(cancelButton)
            NSLayoutConstraint.activate([
                cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                cancelButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ])
        }

        @objc private func cancelLoading() {
            presentationTask?.cancel()
            onFinish(nil)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !didPresent else { return }
            didPresent = true
            presentationTask = Task { @MainActor in
                do {
                    let content = try await discovery.content(for: .payment(.howToTap))
                    try Task.checkCancellation()
                    cancelButton.isHidden = true
                    try await discovery.presentContent(content, from: self)
                    onFinish(nil)
                } catch is CancellationError {
                    return
                } catch {
                    onFinish("The Apple guide couldn't be opened on this device. Try again on an iPhone with Tap to Pay support.")
                }
            }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isBeingDismissed { presentationTask?.cancel() }
        }
    }
}
