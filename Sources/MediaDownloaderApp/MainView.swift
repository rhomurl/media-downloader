import SwiftUI
import DownloaderCore
import DownloaderPresentation

struct MainView: View {
    @Bindable var model: AppModel
    @FocusState private var urlFocused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Media Downloader").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text("Save one recorded video as MP4 or MP3.").foregroundStyle(.secondary)
                DependencyView(model: model)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Video URL", text: $model.rawURL, prompt: Text("https://…"))
                        .textFieldStyle(.roundedBorder).focused($urlFocused)
                        .accessibilityLabel("Video URL")
                        .onSubmit { if model.canPreview { Task { await model.preview() } } }
                    Picker("Browser cookies", selection: $model.browser) {
                        Text("None").tag(CookieBrowser.none)
                        Text("Chrome").tag(CookieBrowser.chrome)
                        Text("Brave").tag(CookieBrowser.brave)
                        Text("Firefox").tag(CookieBrowser.firefox)
                    }
                    Text("Cookies are accessed only when you choose Preview or Download with a browser selected. Browser choice is never saved.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.browser == .brave {
                        Picker("Brave profile", selection: $model.braveProfileID) {
                            Text("Choose a profile").tag(String?.none)
                            ForEach(model.braveProfiles) { profile in
                                Text(verbatim: "\(profile.name) (\(profile.id))").tag(Optional(profile.id))
                            }
                        }
                        .disabled(model.isLoadingProfiles)
                        if model.isLoadingProfiles { ProgressView("Loading Brave profiles") }
                        if let issue = model.profileIssue {
                            Text(verbatim: AppIssueClassifier.message(for: issue)).foregroundStyle(.red)
                        }
                        if !model.isLoadingProfiles {
                            Button("Refresh profiles") { Task { await model.refreshBraveProfiles() } }
                        }
                    }
                    Button("Preview") { Task { await model.preview() } }
                        .disabled(!model.canPreview).keyboardShortcut("p", modifiers: .command)
                }
                .disabled(model.isBusy || model.isSessionBlocked)
                if let metadata = model.snapshot.metadata { PreviewView(metadata: metadata, thumbnail: model.validatedThumbnail, durationText: model.durationText) }
                Picker("Output", selection: $model.preset) {
                    Text("MP4 video").tag(OutputPreset.mp4)
                    Text("MP3 audio").tag(OutputPreset.mp3)
                }.pickerStyle(.segmented).disabled(model.isBusy)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Destination").font(.headline)
                        Text(verbatim: model.destination.path).font(.callout).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle).accessibilityLabel(model.destination.path)
                    }
                    Spacer()
                    Button("Choose Folder…") { model.selectDestination() }.disabled(model.isBusy)
                }
                HStack {
                    Button("Download") { Task { await model.download() } }
                        .buttonStyle(.borderedProminent).disabled(!model.canDownload)
                        .keyboardShortcut("d", modifiers: .command)
                    Button("Cancel") { Task { await model.cancel() } }.disabled(!model.canCancel)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    if model.snapshot.phase == .succeeded {
                        Button("Show in Finder") { model.revealOutput() }
                    }
                }
                DownloadStatusView(model: model)
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 580)
        .onAppear { urlFocused = true }
    }
}
