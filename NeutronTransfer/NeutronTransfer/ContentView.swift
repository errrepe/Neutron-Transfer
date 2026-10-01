//
//  ContentView.swift
//  NeutronTransfer
//
//  Created by Raphael Medeiros on 29/09/26.
//

import SwiftUI

struct ContentView: View {
    @State private var model = LoginViewModel()
    @State private var queue = TransferQueue(storeURL: TransferQueue.defaultStoreURL())
    @State private var activity = TransferActivityStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Neutron Transfer")
                .font(.title)
            Text("This is a third-party application not officially supported by Proton.")
                .font(.caption)
                .foregroundStyle(.secondary)
            switch model.state {
            case .signedOut, .signingIn, .error:
                TextField("Email or username", text: $model.username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                Button(model.state == .signingIn ? "Signing in…" : "Sign in") {
                    Task { await model.signIn() }
                }
                .disabled(model.state == .signingIn)
                if case let .error(msg) = model.state {
                    Text(msg).font(.caption).foregroundStyle(.orange)
                }
            case .needs2FA:
                Text("Two-factor code required").font(.headline)
                TextField("TOTP code", text: $model.totp)
                    .textFieldStyle(.roundedBorder)
                Button("Verify") {
                    Task { await model.submit2FA() }
                }
            case let .signedIn(uid):
                Text("Signed in: \(uid)").font(.headline)
                TabView {
                    DriveBrowserView(sessions: model.sessionManager, addressKeys: model.addressKeys, activity: activity)
                        .tabItem { Label("Browse", systemImage: "folder") }
                    TransferQueueView(queue: queue, sessions: model.sessionManager, addressKeys: model.addressKeys, activity: activity)
                        .tabItem { Label("Transfers", systemImage: "arrow.up.arrow.down.circle") }
                }
            }
            Spacer()
            Text("F6 alpha: uploads + downloads in Transfers; browser refreshes after operations.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }
}

#Preview {
    ContentView()
}
