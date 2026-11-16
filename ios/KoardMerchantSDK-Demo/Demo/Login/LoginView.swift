import SwiftUI
import KoardSDK

struct LoginView: View {
    @State private var viewModel: LoginViewModel
    @FocusState private var focusedField: Field?

    /// Identifies which text field is currently focused so the keyboard
    /// "Done" toolbar (and the Return key on the merchant-code field) can
    /// move focus forward without us having to thread bindings around.
    private enum Field: Hashable { case code, pin }

    init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("koard").font(.system(size: 34, weight: .bold)).tracking(-1.5)
                        Spacer()
                        Text("POINT OF SALE").font(.system(size: 10, weight: .bold)).tracking(2)
                            .foregroundStyle(POSDesign.muted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ready for service.").font(.system(size: 32, weight: .bold))
                        Text("Sign in to open your register.")
                            .font(.subheadline).foregroundStyle(POSDesign.muted)
                    }
                    .padding(.top, 24)
                }
                .foregroundStyle(POSDesign.ink)
                .padding(.horizontal, 20)
                .padding(.top, 36)

                // Credential Input Fields
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Merchant Code")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField("Enter merchant code", text: $viewModel.merchantCode)
                            .accessibilityIdentifier("login.code")
                            .font(.body.weight(.medium))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 54)
                            .background(POSDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(POSDesign.line, lineWidth: 1))
                            // Modern iOS 15+ replacement for the deprecated
                            // .autocapitalization(.none), which was the source
                            // of the "variant selector cell" console warnings.
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(nil)
                            .keyboardType(.asciiCapable)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .code)
                            .onSubmit { focusedField = .pin }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Merchant PIN")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        SecureField("Enter PIN", text: $viewModel.merchantPin)
                            .accessibilityIdentifier("login.pin")
                            .font(.body.weight(.medium))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 54)
                            .background(POSDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(POSDesign.line, lineWidth: 1))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(nil)
                            .keyboardType(.numberPad)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .pin)
                            .onSubmit {
                                focusedField = nil
                                Task { await viewModel.authenticate() }
                            }
                    }
                    if focusedField != nil {
                        HStack {
                            Spacer()
                            Button("Done") { focusedField = nil }
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                                .foregroundStyle(.koardGreen)
                                .accessibilityIdentifier("login.done")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .toolbar {
                    // Number pad has no return key — keyboard Done lets the
                    // user dismiss the PIN keyboard without tapping outside.
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focusedField = nil }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.koardGreen)
                    }
                }

                // Login Button
                AsyncButton {
                    focusedField = nil
                    await viewModel.authenticate()
                } label: {
                    HStack(spacing: 12) {
                        if viewModel.isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Open register")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.koardGreen)
                .disabled(viewModel.isAuthenticating || !viewModel.canLogin)
                .padding(.horizontal, 20)

                // Error Message
                if !viewModel.authenticationError.isEmpty {
                    Text(viewModel.authenticationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer(minLength: 16)
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("merchant.login")
        .background {
            KoardBackgroundView()
                .ignoresSafeArea()
        }
    }
}

#Preview {
    LoginView(
        viewModel: .init(
            koardMerchantService: .mockMerchantService,
            onAuthenticationSuccess: {}
        )
    )
}
