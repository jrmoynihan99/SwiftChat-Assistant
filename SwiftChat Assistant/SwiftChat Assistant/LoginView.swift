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
    @State private var showPassword: Bool = false

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
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 32) {
                        // Hero section
                        VStack(spacing: 12) {
                            Text("SwiftChat")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundStyle(.white)
                            
                            Text("Your personal AI assistant")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.top, 60)
                        
                        // Forms
                        VStack(spacing: 20) {
                            Group {
                                if mode == .login { loginForm } else { signupForm }
                            }
                            .transition(.opacity)
                            .id(mode) // This forces SwiftUI to treat them as different views
                            
                            // Error message
                            if let errorMessage {
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                            }
                            
                            // Primary button right after form
                            primaryButton(
                                title: mode == .login ? "Log In" : "Create Account",
                                isLoading: isLoading,
                                action: submit
                            )
                        }
                        .animation(.easeInOut(duration: 0.3), value: mode)
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 120) // Space for bottom toggle
                }
                .scrollDismissesKeyboard(.interactively)
                
                Spacer()
                
                // Bottom toggle pinned to bottom
                VStack(spacing: 16) {
                    // Mode picker - taller design with segmented style
                    Picker("Mode", selection: $mode) {
                        ForEach(AuthMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(height: 50)
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 24)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                )
            }
        }
        .onChange(of: mode) { _, newMode in
            DispatchQueue.main.async { focusFirstEmptyField(for: newMode) }
        }
    }

    private var loginForm: some View {
        VStack(spacing: 16) {
            // Email field
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20)
                
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .loginEmail)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // Password field
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20)
                
                if showPassword {
                    TextField("Password", text: $password)
                        .textContentType(nil)
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .loginPassword)
                } else {
                    SecureField("Password", text: $password)
                        .textContentType(nil)
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .loginPassword)
                }
                
                Button {
                    let currentField = focusedField
                    showPassword.toggle()
                    // Restore focus after toggling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        focusedField = currentField
                    }
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .onTapGesture { hasUserFocusedAField = true }
    }

    private var signupForm: some View {
        VStack(spacing: 16) {
            // First and Last name
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20)
                    
                    TextField("First", text: $firstName)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .signupFirstName)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                
                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20)
                    
                    TextField("Last", text: $lastName)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .signupLastName)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            
            // Email field
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20)
                
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .signupEmail)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // Password field
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20)
                
                if showPassword {
                    TextField("Password", text: $password)
                        .textContentType(nil)
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .signupPassword)
                } else {
                    SecureField("Password", text: $password)
                        .textContentType(nil)
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .signupPassword)
                }
                
                Button {
                    let currentField = focusedField
                    showPassword.toggle()
                    // Restore focus after toggling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        focusedField = currentField
                    }
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // Phone number field
            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20)
                
                TextField("Phone", text: $phoneNumber)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .signupPhone)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
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
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(isLoading || !isValid)
        .opacity(isLoading || !isValid ? 0.5 : 1)
    }
}

#Preview {
    LoginView { _, _ in }
}
