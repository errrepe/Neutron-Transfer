//
//  NeutronTransferApp.swift
//  NeutronTransfer
//
//  Created by Raphael Medeiros on 29/09/26.
//

import SwiftUI

@main
struct NeutronTransferApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView().environment(session)
        }
        .defaultSize(width: 1100, height: 700)
    }
}
