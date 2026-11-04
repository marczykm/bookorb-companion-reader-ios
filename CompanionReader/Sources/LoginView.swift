import SwiftUI

struct LoginView: View {
    @EnvironmentObject var api: ServerAPI
    @AppStorage("lastServer") private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("books.example.com", text: $server)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
                Section("Account") {
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button { signIn() } label: {
                    HStack { Text("Sign in"); if busy { ProgressView() } }
                }.disabled(busy || server.isEmpty || username.isEmpty || password.isEmpty)
            }
            .navigationTitle("Companion Reader")
        }
    }

    private func signIn() {
        busy = true; error = nil
        Task {
            do { try await api.login(server: server, username: username, password: password) }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
