//
//  SheetWindowContainer.swift
//  CleanMyDigital
//

import SwiftUI

/// The one motion curve for every state change that would otherwise hard-cut
/// — empty state ↔ results, a banner appearing/disappearing, a list
/// repopulating after an apply/correction/rescan, a disclosure row expanding.
/// Critically damped (no bounce/overshoot), restrained for a macOS utility;
/// used everywhere via `View.consistentAnimation(_:)` below rather than each
/// call site inventing its own curve and duration.
extension Animation {
    static var uiStateChange: Animation { .smooth(duration: 0.3) }
}

extension View {
    /// Animates `value`'s changes with `Animation.uiStateChange` — or, under
    /// Reduce Motion, a quick plain cross-fade instead of the spring, since
    /// Reduce Motion asks for less movement, not silence.
    func consistentAnimation(_ value: some Equatable) -> some View {
        modifier(ConsistentAnimation(value: value))
    }
}

private struct ConsistentAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .linear(duration: 0.12) : .uiStateChange, value: value)
    }
}

/// The shared shell every auxiliary window (Rename Files, Collect into
/// Folders, Find Duplicates, Check Album Completeness, Apply Found Matches)
/// was independently reimplementing: a header (an optional title, a
/// subtitle, and a "Done" button that dismisses this window by id), a
/// divider, the window's own content, a divider, and the window's own
/// footer. Pulled out once these five drifted into near-identical code with
/// no behavioral difference — three of them even converged on the same
/// frame by copy-paste, while the "reason" for the other two's slightly
/// different ideal width had nothing to do with anything they show.
///
/// `title` is optional because `ApplyFoundMatchesSheetView` deliberately has
/// none — its window's own titlebar already says "Apply Found Matches", so
/// a second headline above the subtitle was a pure duplicate (fixed in an
/// earlier pass). Every other window keeps its title.
struct SheetWindowContainer<Content: View, Footer: View>: View {
    var title: String?
    let subtitle: String
    /// The window id this container's own `WindowGroup` was registered
    /// under in `CleanMyDigitalApp.swift` — what "Done" dismisses.
    let windowID: String
    var size: SheetWindowSize = .standard
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content()
            Divider()
            footer()
        }
        .frame(minWidth: size.minWidth, idealWidth: size.idealWidth, maxWidth: .infinity,
               minHeight: size.minHeight, idealHeight: size.idealHeight, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title).font(.headline)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismissWindow(id: windowID) }
                // Esc closes the window, the macOS convention for a
                // review window that writes nothing by itself.
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }
}

/// Named presets rather than each window inventing its own ideal size.
/// `.standard` is the default every window should reach for; `.wide` is for
/// a genuine need for more room — a column-heavy table
/// (`DuplicatesSheetView`) — and `.extraWide` for a side-by-side layout that
/// needs two full comparison columns at once (`ApplyFoundMatchesSheetView`)
/// — not an arbitrary tweak.
enum SheetWindowSize {
    case standard
    case wide
    case extraWide

    var minWidth: CGFloat {
        switch self {
        case .extraWide: 860
        case .standard, .wide: 640
        }
    }

    var minHeight: CGFloat { 440 }

    var idealWidth: CGFloat {
        switch self {
        case .standard: 760
        case .wide: 860
        case .extraWide: 1040
        }
    }

    var idealHeight: CGFloat {
        switch self {
        case .standard: 520
        case .wide: 600
        case .extraWide: 640
        }
    }
}
