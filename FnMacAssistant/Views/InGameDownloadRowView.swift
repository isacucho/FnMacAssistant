//
//  InGameDownloadRowView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 13/11/25.
//

import SwiftUI

struct InGameDownloadRowView: View {
    let title: String
    let description: String
    let progress: Double
    let isActive: Bool
    
    let resetAction: () -> Void
    let startAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Title
            Text(title)
                .font(.title2).bold()

            // Subtitle / status text
            Text(description)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isActive {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("Cancel Download") {
                            cancelAction()   // NO POPUP HERE
                        }
                        .foregroundColor(.red)
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                HStack {

                    Button("Start Download") {
                        startAction()
                    }
                    .buttonStyle(.borderedProminent)

                    // NEW — Show reset button only when fully completed
                    if progress >= 1.0 {
                        Button("Reset Download") {
                            resetAction()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }

                    Spacer()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}
