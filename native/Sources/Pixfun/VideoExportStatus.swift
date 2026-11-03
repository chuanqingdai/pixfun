import SwiftUI

struct VideoExportStatus: View {
    @EnvironmentObject var store: WorkspaceStore
    var runID: String?
    var body: some View {
        if let job = store.videoExport, job.runId == runID {
            HStack(spacing: 5) {
                if job.busy || store.videoExportSaving {
                    ProgressView().controlSize(.mini)
                    Text("\(job.qualityLabel) · \(min(job.completed, job.total))/\(job.total)").font(.pixfun(11)).monospacedDigit()
                    if job.busy {
                        Button { store.cancelVideoExport() } label: { Image(systemName:"xmark") }
                            .help("Cancel export").accessibilityLabel("Cancel export")
                    }
                } else if let destination = store.exportedVideoURL, job.status == "completed" {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([destination]) } label: {
                        Label(job.qualityLabel, systemImage:"checkmark.circle")
                    }.help("Show exported video in Finder").accessibilityLabel("Show exported video in Finder")
                }
            }.buttonStyle(PixfunButtonStyle(kind:.quiet))
        }
    }
}
