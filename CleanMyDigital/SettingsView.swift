//
//  SettingsView.swift
//  CleanMyDigital
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("discogsToken") private var discogsToken = ""

    var body: some View {
        Form {
            Section {
                SecureField("Personal Access Token", text: $discogsToken)
                Link("Get a token from Discogs…",
                     destination: URL(string: "https://www.discogs.com/settings/developers")!)
                    .font(.caption)
            } header: {
                Text("Discogs")
            } footer: {
                Text("Used to look up missing metadata for flagged files. Stored locally in this app's preferences.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
    }
}

#Preview {
    SettingsView()
}
