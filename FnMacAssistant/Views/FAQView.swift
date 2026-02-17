//
//  FAQView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 02/04/26.
//

import SwiftUI

struct FAQView: View {
    private let items: [FAQItem] = [
        FAQItem(
            question: "I'm getting a connection or storage error when opening Fortnite.",
            answer: """
To fix this, you need to download the game data using FnMacAssistant.

1. Open FnMacAssistant and select the "Game Assets" tab.
2. Select 'base-game' and your preferred game modes (note: you will need to download the 'cosmetics' layer to play most gamemodes). 
3. Click the "Download Selected Assets" button.
4. Wait for the download to complete, and once it's done open the game. 
"""
        ),
        FAQItem(
            question: "How do I update the game?",
            answer: """
Follow these steps to update Fortnite:

1. Download the updated IPA.
2. Install it through Feather or Sideloadly using the same Apple ID you used previously.
3. On FnMacAssistant, go to the 'Patch' tab and click on 'Apply Patch'.
4. If prompted, go to 'System Settings > Privacy & Security', scroll down and click on 'Open Anyway'
5. Download game files through the Game Assets tab, or with the background download method.
"""
        ),
        FAQItem(
            question: "“Fortnite” cannot be opened because the developer did not intend for it to be run on this Mac.",
            answer: """
This error might appear 7 days after you first installed. This happens because sideloaded apps expire every 7 days. To fix this: 

1. Delete Fortnite.app from Applications.
2. Reinstall the IPA using Sideloadly or PlumeImpactor.
3. Patch using FnMacAssistant.
4. Open Fortnite.
"""
        ),
        FAQItem(
            question: "FnMacAssistant cannot find Fortnite's container",
            answer: """
Grant Full Disk Access to FnMacAssistant:

1. System Settings > Privacy & Security > Full Disk Access.
2. Add FnMacAssistant and enable it.
3. Restart FnMacAssistant and patch again.
"""
        ),
        FAQItem(
            question: "Fortnite keeps crashing even after patching",
            answer: """
This usually means your macOS version isn't supported. Update macOS and try again.
"""
        ),
        FAQItem(
            question: "What's the difference between the IPAs?",
            answer: """
You can see what each IPA contains when selecting it in the 'IPA Downloads' tab.
"""
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                Text("Quick answers to common setup and troubleshooting questions.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                ForEach(items) { item in
                    FAQCard(item: item)
                }

                Spacer()
            }
            .padding(24)
        }
    }
}

private struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

private struct FAQCard: View {
    let item: FAQItem
    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(item.question)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }

                if isExpanded {
                    Text(item.answer)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1))
        )
    }
}

private extension FAQView {
    var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("FAQ")
                    .font(.largeTitle)
                    .bold()
                Text("Common answers")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}
