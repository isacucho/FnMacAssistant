//
//  HomeView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 03/02/26.
//

import SwiftUI
import AppKit

struct HomeView: View {
    @Binding var selection: SidebarSection
    @AppStorage("homeGetStartedCollapsed") private var isGetStartedCollapsed = false
    private let githubURL = URL(string: "https://github.com/isacucho/FnMacAssistant")
    private let discordURL = URL(string: "https://discord.gg/nfEBGJBfHD")
    private let readmeURL = URL(string: "https://github.com/isacucho/FnMacAssistant#readme")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topSection
                firstStepsSection
                supportSection
                creditsSection
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private var topSection: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("FnMacAssistant")
                    .font(.system(size: 42, weight: .bold))

                Text("Fortnite for Apple Silicon Macs.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if let discordURL {
                        socialLinkButton(
                            title: "Join the Discord",
                            systemImage: "person.2.fill",
                            tint: .blue,
                            destination: discordURL
                        )
                    }

                    if let githubURL {
                        socialLinkButton(
                            title: "Open GitHub",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            tint: .gray,
                            destination: githubURL
                        )
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }

    private var firstStepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: isGetStartedCollapsed ? "chevron.right" : "chevron.down")
                    .foregroundColor(.secondary)
            }

            if !isGetStartedCollapsed {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            stepCard(
                                number: "1",
                                title: "Download IPA",
                                detail: "Get the Fortnite IPA from IPA Downloads.",
                                links: [],
                                actionTitle: "Open IPA Downloads",
                                action: { selection = .downloads }
                            )

                            stepCard(
                                number: "2",
                                title: "Install IPA",
                                detail: "",
                                links: [
                                    LinkItem(
                                        markdownText: "Sideload the IPA with [Sideloadly](https://sideloadly.io) or [PlumeImpactor](https://github.com/khcrysalis/PlumeImpactor)."
                                    )
                                ],
                                actionTitle: "Install With Sideload Tool",
                                action: nil
                            )

                            stepCard(
                                number: "3",
                                title: "Patch",
                                detail: "Open the Patcher and patch Fortnite.",
                                links: [],
                                actionTitle: "Open Patcher",
                                action: { selection = .patch }
                            )

                            stepCard(
                                number: "4",
                                title: "Install Contents",
                                detail: "Use Update Assistant to install game contents.",
                                links: [],
                                actionTitle: "Open Update Assistant",
                                action: { selection = .updateAssistant }
                            )
                        }
                    }

                    if let readmeURL {
                        Text(.init("Full guide on the [Github page](\(readmeURL.absoluteString))."))
                            .font(.system(size: 12, weight: .medium))
                    }

                    Label("Do not open Fortnite while FnMacAssistant is installing game contents.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, isGetStartedCollapsed ? 12 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isGetStartedCollapsed.toggle()
            }
        }
        .accessibilityAddTraits(.isButton)
    }

    private func stepCard(
        number: String,
        title: String,
        detail: String,
        links: [LinkItem],
        actionTitle: String,
        action: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(links) { item in
                if let markdownText = item.markdownText {
                    Text(.init(markdownText))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let url = item.url {
                    Link(item.title, destination: url)
                        .font(.system(size: 12, weight: .medium))
                }
            }

            Spacer(minLength: 0)

            if let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.bordered)
                .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(12)
        .frame(width: 190, height: 137, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Credits")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    discreteCreditCell(name: "isacucho", role: "Main Developer")
                    discreteCreditCell(name: "rt2746 & Inventor", role: "FnMacTweak")
                    discreteCreditCell(name: "Sneakyf1shy", role: "fort-dl")
                    discreteCreditCell(name: "altermine", role: "Update Assistant")
                    discreteCreditCell(name: "VictorWads", role: "External drive support")
                    discreteCreditCell(name: "Jasonsika", role: "App icon")
                }
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func discreteCreditCell(name: String, role: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
            Text(role)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.16))
                        .frame(width: 24, height: 24)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.green)
                }

                Text("Support Development")
                    .font(.system(size: 18, weight: .semibold))
            }

            Text("If you appreciate FnMacAssistant, consider supporting continued development and support by using my creator code in the Item Shop or the Epic Games Store.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("Creator code")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Text("ISACUCHO")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.green.opacity(0.14))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.green.opacity(0.35), lineWidth: 1)
                    )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }

    private func socialLinkButton(
        title: String,
        systemImage: String,
        tint: Color,
        destination: URL
    ) -> some View {
        Link(destination: destination) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                        .frame(width: 22, height: 22)
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.95))
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LinkItem: Identifiable {
    let id = UUID()
    let title: String
    let url: URL?
    let markdownText: String?

    init(title: String = "", url: URL? = nil, markdownText: String? = nil) {
        self.title = title
        self.url = url
        self.markdownText = markdownText
    }
}
