import SwiftUI

enum AuthMode: String, CaseIterable {
    case login = "Log In"
    case signup = "Sign Up"
}

struct LoginView: View {
    @State private var mode: AuthMode = .login

    // Login fields
    @State private var email: String = ""
    @State private var password: String = ""

    // Signup fields
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var phoneNumber: String = ""

    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    @State private var hasUserFocusedAField = false
    @State private var rememberMe: Bool = false

    let onAuthenticated: (_ loginTokens: AuthWithTokensResponse?, _ user: BackendUser?) -> Void

    enum Field {
        case loginEmail, loginPassword
        case signupFirstName, signupLastName, signupEmail, signupPassword, signupPhone
    }

    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("SwiftChat")
                .font(.largeTitle.bold())
                .padding(.top, 24)

            // Mode picker
            Picker("Mode", selection: $mode) {
                ForEach(AuthMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            // Forms
            Group {
                if mode == .login { loginFormSimple } else { signupFormSimple }
            }

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Primary button
            primaryButton(title: mode == .login ? "Log In" : "Create Account", isLoading: isLoading, action: submit)
                .padding(.top, 8)

            Spacer()
        }
        .padding()
        .onChange(of: mode) { _, newMode in
            DispatchQueue.main.async { focusFirstEmptyField(for: newMode) }
        }
    }

    private var loginFormSimple: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .loginEmail)
            SecureField("Password", text: $password)
                .textContentType(nil)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .loginPassword)
        }
        .onTapGesture { hasUserFocusedAField = true }
    }

    private var signupFormSimple: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("First name", text: $firstName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .signupFirstName)
                TextField("Last name", text: $lastName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .signupLastName)
            }
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .signupEmail)
            SecureField("Password", text: $password)
                .textContentType(nil)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .signupPassword)
            TextField("Phone number", text: $phoneNumber)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .signupPhone)
        }
    }

    private func focusFirstEmptyField(for mode: AuthMode) {
        guard hasUserFocusedAField else { return }
        switch mode {
        case .login:
            if email.isEmpty { focusedField = .loginEmail }
            else if password.isEmpty { focusedField = .loginPassword }
            else { focusedField = .loginEmail }
        case .signup:
            if firstName.isEmpty { focusedField = .signupFirstName }
            else if lastName.isEmpty { focusedField = .signupLastName }
            else if email.isEmpty { focusedField = .signupEmail }
            else if password.isEmpty { focusedField = .signupPassword }
            else if phoneNumber.isEmpty { focusedField = .signupPhone }
            else { focusedField = .signupFirstName }
        }
    }

    private var isValid: Bool {
        switch mode {
        case .login:
            return !email.isEmpty && !password.isEmpty
        case .signup:
            return !firstName.isEmpty && !lastName.isEmpty && !email.isEmpty && !password.isEmpty && !phoneNumber.isEmpty
        }
    }

    private func submit() {
        errorMessage = nil
        isLoading = true
        Task { await performAuth() }
    }

    @MainActor
    private func performAuth() async {
        defer { isLoading = false }
        switch mode {
        case .login:
            do {
                let tokens = try await AuthService.shared.login(email: email, password: password)
                onAuthenticated(tokens, nil)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Login failed. Please try again."
            }
        case .signup:
            do {
                let tokens = try await AuthService.shared.signup(firstName: firstName, lastName: lastName, email: email, password: password, phoneNumber: phoneNumber)
                onAuthenticated(tokens, tokens.user)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Signup failed. Please try again."
            }
        }
    }
    
    private func primaryButton(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(title)
                        .fontWeight(.semibold)
                }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [Color(.systemPink), Color(.systemOrange)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 0.75)
        )
        .shadow(color: .indigo.opacity(0.35), radius: 12, x: 0, y: 6)
        .disabled(isLoading || !isValid)
        .opacity(isLoading || !isValid ? 0.85 : 1)
    }
}

#Preview {
    LoginView { _, _ in }
}
