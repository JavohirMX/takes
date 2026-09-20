import Photos
import SwiftUI
import UIKit

struct ShareRecapSheet: View {
    let title: String
    let whitePlayer: String?
    let blackPlayer: String?
    let opening: String?
    let result: String
    let finalFen: String
    let currentFen: String
    let plies: Int
    let whiteAccuracy: Double?
    let blackAccuracy: Double?
    let whiteElo: Int?
    let blackElo: Int?
    let date: Date

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTheme: RecapCardTheme = .dark
    @State private var selectedFormat: RecapCardFormat = .card
    @State private var showElo = true
    @State private var showAccuracy = true
    @State private var showOpening = true
    @State private var showMoveCount = true
    @State private var showDate = true
    @State private var showCoordinates = true
    @State private var showBranding = true
    @State private var useCurrentFen = false

    @State private var shareItems: [Any] = []
    @State private var showSystemShare = false
    @State private var toastMessage: String?

    private var activeFen: String {
        useCurrentFen ? currentFen : finalFen
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Live Card Preview
                        cardPreview
                            .padding(.top, 12)

                        // Theme Selection
                        themeSelector

                        // Format Selection
                        formatSelector

                        // Position Toggle (if replay move differs from final position)
                        if finalFen != currentFen {
                            positionToggle
                        }

                        // Customization Toggles
                        customizationOptions

                        // Action Buttons
                        actionButtons
                            .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16)
                }

                if let toast = toastMessage {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.surface, in: Capsule())
                            .overlay { Capsule().stroke(Theme.border, lineWidth: 1) }
                            .shadow(radius: 10)
                            .padding(.bottom, 32)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: toastMessage)
                }
            }
            .navigationTitle("Recap Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        shareRenderedImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Share")
                }
            }
            .sheet(isPresented: $showSystemShare) {
                ShareSheet(items: shareItems)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var cardView: GameRecapCardView {
        GameRecapCardView(
            title: title,
            whitePlayer: whitePlayer,
            blackPlayer: blackPlayer,
            opening: opening,
            result: result,
            finalFen: activeFen,
            plies: plies,
            whiteAccuracy: whiteAccuracy,
            blackAccuracy: blackAccuracy,
            whiteElo: whiteElo,
            blackElo: blackElo,
            date: date,
            theme: selectedTheme,
            format: selectedFormat,
            showElo: showElo,
            showAccuracy: showAccuracy,
            showOpening: showOpening,
            showMoveCount: showMoveCount,
            showDate: showDate,
            showCoordinates: showCoordinates,
            showBranding: showBranding
        )
    }

    private var cardPreview: some View {
        VStack {
            cardView
                .scaleEffect(previewScale)
                .frame(
                    width: selectedFormat.dimensions.width * previewScale,
                    height: selectedFormat.dimensions.height * previewScale
                )
                .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(260, selectedFormat.dimensions.height * previewScale + 20))
        .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border.opacity(0.4), lineWidth: 1)
        }
    }

    private var previewScale: CGFloat {
        switch selectedFormat {
        case .card: 0.72
        case .square: 0.78
        case .story: 0.52
        }
    }

    private var themeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THEME")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                ForEach(RecapCardTheme.allCases) { theme in
                    Button {
                        selectedTheme = theme
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(theme.backgroundColor)
                                .frame(width: 14, height: 14)
                                .overlay {
                                    Circle().stroke(theme.borderColor, lineWidth: 1)
                                }
                            Text(theme.rawValue)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedTheme == theme ? Theme.accent : Theme.surface,
                            in: Capsule()
                        )
                        .foregroundStyle(
                            selectedTheme == theme ? Theme.background : Theme.textPrimary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formatSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FORMAT")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary)

            Picker("Format", selection: $selectedFormat) {
                ForEach(RecapCardFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var positionToggle: some View {
        Toggle(isOn: $useCurrentFen) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show Current Replay Position")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Show board position at current replay move instead of final position.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var customizationOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CUSTOMIZE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 0) {
                toggleRow(title: "Estimated Elo", isOn: $showElo)
                Divider().background(Theme.border.opacity(0.4))
                toggleRow(title: "Move Accuracy %", isOn: $showAccuracy)
                Divider().background(Theme.border.opacity(0.4))
                toggleRow(title: "Opening Name", isOn: $showOpening)
                Divider().background(Theme.border.opacity(0.4))
                toggleRow(title: "Move Count", isOn: $showMoveCount)
                Divider().background(Theme.border.opacity(0.4))
                toggleRow(title: "Date & Time", isOn: $showDate)
                Divider().background(Theme.border.opacity(0.4))
                toggleRow(title: "Board Coordinates", isOn: $showCoordinates)
                Divider().background(Theme.border.opacity(0.4))
                toggleRow(title: "Takes Branding", isOn: $showBranding)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.border.opacity(0.4), lineWidth: 1)
            }
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                shareRenderedImage()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Image")
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            HStack(spacing: 12) {
                Button {
                    saveImageToPhotos()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save to Photos")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    }
                }

                Button {
                    copyImageToClipboard()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Image")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    }
                }
            }
        }
    }

    @MainActor
    private func renderCardImage() -> UIImage? {
        let card = cardView
        let targetSize = selectedFormat.dimensions
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        renderer.proposedSize = ProposedViewSize(width: targetSize.width, height: targetSize.height)
        if let image = renderer.uiImage {
            return image
        }

        let hosting = UIHostingController(rootView: card)
        hosting.view.bounds = CGRect(origin: .zero, size: targetSize)
        hosting.view.backgroundColor = .clear
        let uiRenderer = UIGraphicsImageRenderer(size: targetSize)
        return uiRenderer.image { _ in
            hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
        }
    }

    @MainActor
    private func shareRenderedImage() {
        guard let image = renderCardImage() else { return }
        shareItems = [image]
        showSystemShare = true
    }

    @MainActor
    private func saveImageToPhotos() {
        guard let image = renderCardImage() else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                showToast("Photo library access denied")
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            showToast("Saved to Photos!")
        }
    }

    @MainActor
    private func copyImageToClipboard() {
        guard let image = renderCardImage() else { return }
        UIPasteboard.general.image = image
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showToast("Image copied to clipboard!")
    }

    private func showToast(_ message: String) {
        Task { @MainActor in
            toastMessage = message
            try? await Task.sleep(for: .seconds(2))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}
