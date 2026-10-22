import SwiftUI
import DownloaderCore

struct PreviewView: View {
    let metadata: VideoMetadata
    let thumbnail: URL?
    let durationText: String?
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: thumbnail) { phase in
                if let image = phase.image { image.resizable().scaledToFit() }
                else { Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary) }
            }
            .frame(width: 120, height: 80).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: metadata.title).font(.headline).lineLimit(3)
                    .accessibilityLabel(metadata.title).textSelection(.enabled)
                if let durationText {
                    Text(verbatim: durationText)
                        .font(.callout).foregroundStyle(.secondary).accessibilityLabel("Duration \(durationText)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
