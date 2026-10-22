import AppKit
import SwiftUI
import DownloaderCore
import DownloaderPresentation

struct DependencyView: View {
    @Bindable var model: AppModel
    var allowsOverrides = false
    private func path(for name: String, tools: ResolvedTools) -> String {
        switch name {
        case "ytdlp": tools.ytdlp.path
        case "ffmpeg": tools.ffmpeg.path
        case "ffprobe": tools.ffprobe.path
        default: tools.deno.path
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Required Tools").font(.headline)
                Spacer()
                Button("Check Again") { Task { await model.checkDependencies() } }
                    .disabled(!model.canCheckDependencies)
            }
            if model.isSessionBlocked {
                Text(verbatim: model.statusText).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else if model.isCheckingDependencies {
                ProgressView("Checking required tools")
            } else if let report = model.dependencyReport {
                if let tools = report.tools, report.problems.isEmpty {
                    Text("Tools are ready.").foregroundStyle(.secondary)
                    DisclosureGroup("Paths and versions") {
                        ForEach(AppModel.toolNames, id: \.self) { name in
                            VStack(alignment: .leading) {
                                Text(verbatim: "\(name == "ytdlp" ? "yt-dlp" : name) \(report.versions[name == "ytdlp" ? "yt-dlp" : name] ?? "")").font(.callout.bold())
                                Text(verbatim: path(for: name, tools: tools)).font(.caption).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let ejs = report.versions["ejs"] { Text(verbatim: "EJS \(ejs)").font(.caption) }
                    }
                } else {
                    Text(verbatim: AppIssueClassifier.message(for: .dependency)).foregroundStyle(.red)
                    ForEach(Array(report.problems.enumerated()), id: \.offset) { _, problem in
                        Text(verbatim: "\(problem.tool): \(safeProblem(problem.code))").font(.callout)
                    }
                    Text("Install or maintain yt-dlp, FFmpeg and Deno with your package manager. yt-dlp also needs its local EJS component. The app never installs or updates tools.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else { Text("Check the required local tools before previewing.").foregroundStyle(.secondary) }
            if allowsOverrides {
                Divider()
                Text("Tool paths").font(.headline)
                Text("Choose absolute executables for these named tools. FFmpeg and FFprobe must keep their original names in the same folder.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(AppModel.toolNames, id: \.self) { name in
                    HStack {
                        Text(verbatim: name == "ytdlp" ? "yt-dlp" : name).frame(width: 64, alignment: .leading)
                        Text(verbatim: model.toolOverrides[name]?.path ?? "Automatic Homebrew lookup")
                            .lineLimit(1).truncationMode(.middle).help(model.toolOverrides[name]?.path ?? "Automatic Homebrew lookup")
                        Spacer()
                        Button("Choose…") { chooseTool(name) }.accessibilityLabel("Choose \(name) executable")
                        Button("Reset") {
                            model.setToolOverride(name, url: nil)
                            Task { await model.checkDependencies() }
                        }.disabled(model.toolOverrides[name] == nil)
                    }.disabled(!model.canCheckDependencies)
                }
            }
        }
    }
    private func chooseTool(_ name: String) {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.prompt = "Choose Executable"
        if panel.runModal() == .OK, let url = panel.url {
            model.setToolOverride(name, url: url)
            Task { await model.checkDependencies() }
        }
    }
    private func safeProblem(_ code: String) -> String {
        switch code {
        case "missing": "not found"
        case "not-executable": "choose an executable file"
        case "missing-ejs": "local EJS component is missing"
        case "unsupported-deno": "Deno runtime is unsupported"
        case "helper-directory-mismatch": "FFmpeg and FFprobe must be together"
        case "timeout": "check timed out"
        case "cancelled": "check cancelled"
        default: "tool readiness could not be verified"
        }
    }
}
