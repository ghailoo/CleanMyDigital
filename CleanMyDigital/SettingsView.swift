//
//  SettingsView.swift
//  CleanMyDigital
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            DiscogsSettingsView()
                .tabItem {
                    Label("Discogs", systemImage: "opticaldiscdrive")
                }
            MusicBrainzSettingsView()
                .tabItem {
                    Label("MusicBrainz", systemImage: "music.quarternote.3")
                }
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
    }
}

private struct DiscogsSettingsView: View {
    @AppStorage("discogsToken") private var discogsToken = ""

    var body: some View {
        Form {
            Section {
                SecureField("Personal Access Token", text: $discogsToken)
                Link("Get a token from Discogs…",
                     destination: URL(string: "https://www.discogs.com/settings/developers")!)
                    .font(.caption)
            } footer: {
                Text("Needed to search Discogs releases and see their cover images.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

private struct MusicBrainzSettingsView: View {
    @AppStorage("musicBrainzContact") private var musicBrainzContact = ""

    var body: some View {
        Form {
            Section {
                TextField("Contact Email", text: $musicBrainzContact)
                Link("MusicBrainz API documentation…",
                     destination: URL(string: "https://musicbrainz.org/doc/MusicBrainz_API")!)
                    .font(.caption)
            } footer: {
                Text("MusicBrainz needs no API key, but its etiquette requires a descriptive User-Agent with contact info — this is embedded as \"CleanMyDigital/1.0 (email)\", and requests are limited to 1 per second.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

#Preview {
    SettingsView()
}
