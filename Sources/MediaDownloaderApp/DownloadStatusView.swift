import SwiftUI
import DownloaderCore
import DownloaderPresentation

struct DownloadStatusView: View {
    var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isBusy && !model.isCheckingDependencies {
                if model.snapshot.phase == .downloading, let fraction = model.snapshot.progress?.fractionCompleted {
                    ProgressView(value: fraction).accessibilityLabel(model.busyLabel)
                    if model.snapshot.progress?.totalIsEstimate == true {
                        Text("Transfer total is estimated.").font(.caption).foregroundStyle(.secondary)
                    }
                } else { ProgressView().accessibilityLabel(model.busyLabel) }
            }
            Text(verbatim: model.statusText).foregroundStyle(model.snapshot.issue == nil ? Color.primary : Color.red)
                .fixedSize(horizontal: false, vertical: true).accessibilityLabel(model.statusText)
            if let notice = model.safeNotice { Text(verbatim: notice).font(.callout).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
