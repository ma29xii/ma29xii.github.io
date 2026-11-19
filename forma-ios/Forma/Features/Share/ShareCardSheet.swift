import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareCardPNG: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in card.data }
    }
}

@MainActor
struct RenderedShareCard {
    let transfer: ShareCardPNG
    let image: UIImage

    static func make(display: ShareCardContent.Display, format: ShareCardFormat) -> Self? {
        let renderer = ImageRenderer(content: ShareCardArtwork(display: display, format: format))
        renderer.proposedSize = ProposedViewSize(width: 360, height: format.height)
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let png = image.pngData() else { return nil }
        return Self(transfer: ShareCardPNG(data: png), image: image)
    }
}

struct ShareCardButton: View {
    @State private var selection: Selection?
    private let content: @MainActor () -> ShareCardContent

    init(content: @escaping @MainActor () -> ShareCardContent) {
        self.content = content
    }

    private struct Selection: Identifiable {
        let id = UUID()
        let content: ShareCardContent
    }

    var body: some View {
        Button { selection = Selection(content: content()) } label: {
            Label("Karte teilen", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
        }
        .accessibilityIdentifier("shareCard.open")
        .sheet(item: $selection) { selected in
            ShareCardSheet(content: selected.content)
        }
    }
}

struct ShareCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var format = ShareCardFormat.story
    @State private var hideMeasurements = true
    @State private var prepared: RenderState?
    let content: ShareCardContent

    private struct Request: Equatable, Sendable {
        let format: ShareCardFormat
        let display: ShareCardContent.Display
    }

    private struct RenderState {
        let request: Request
        let card: RenderedShareCard?
    }

    var body: some View {
        let request = Request(format: format, display: content.display(includeMeasurements: !hideMeasurements))
        let matching = prepared.flatMap { $0.request == request ? $0 : nil }
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if typeSize.isAccessibilitySize {
                        formatPicker.pickerStyle(.menu)
                    } else {
                        formatPicker.pickerStyle(.segmented)
                    }
                    if content.hasMeasurements {
                        Toggle("Ohne Gesundheitswerte", isOn: $hideMeasurements)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("shareCard.hideMeasurements")
                    }
                    preview(matching, request: request)
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                if let card = matching?.card {
                    ShareLink(item: card.transfer, preview: SharePreview(request.display.kind.title, image: Image(uiImage: card.image))) {
                        Label("Bild teilen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(Theme.onSelection)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("shareCard.export")
                }
            }
            .formaScreen()
            .navigationTitle("Karte teilen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .task(id: request) {
                guard !Task.isCancelled else { return }
                prepare(request)
            }
        }
    }

    private var formatPicker: some View {
        Picker("Format", selection: $format) {
            ForEach(ShareCardFormat.allCases) { format in
                Text(format.title).tag(format)
            }
        }
        .accessibilityIdentifier("shareCard.format")
    }

    @ViewBuilder private func preview(_ matching: RenderState?, request: Request) -> some View {
        if let card = matching?.card {
            let caption = [request.display.kind.title, request.display.isSample ? "Beispieldaten" : nil, request.display.date]
                .compactMap { $0 }
            let readings = request.display.metrics.map { "\($0.label) \($0.value)" }
            Image(uiImage: card.image)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 12))
                .frame(maxWidth: format == .story ? 216 : 320)
                .accessibilityLabel(Text((caption + readings).joined(separator: ", ")))
        } else if matching != nil {
            VStack(spacing: 8) {
                Text("Die Karte konnte nicht erstellt werden.")
                    .foregroundStyle(Theme.textSecondary)
                Button("Erneut versuchen") { prepare(request) }
                    .frame(minHeight: 44)
            }
            .multilineTextAlignment(.center)
        } else {
            ProgressView("Vorschau wird erstellt")
                .frame(maxWidth: format == .story ? 216 : 320)
                .aspectRatio(format.aspectRatio, contentMode: .fit)
        }
    }

    private func prepare(_ request: Request) {
        let card = RenderedShareCard.make(display: request.display, format: request.format)
        prepared = RenderState(request: request, card: card)
    }
}
