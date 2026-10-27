import SwiftUI
import CoreImage.CIFilterBuiltins

/// One temporary browser session, never persistent phone pairing.
struct SyncPhoneSetupView: View {
    @ObservedObject var model: MediaSyncStore
    @State private var destination: String?
    @State private var attemptedDestination: String?
    @State private var preparing = false
    @State private var cancelled = false
    private var transfer: BrowserPhoneImport? { model.snapshot?.phoneImport }
    private var readyDestination: String? {
        if let destination { return destination }
        return model.snapshot?.working?.connected == true ? model.snapshot?.working?.path : nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Save location").font(.pixfun(13, semibold: true))
                Text("Verified copies are saved here. Originals stay on your phone.")
                    .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                SyncSaveLocationCard(destination: destination ?? model.snapshot?.working?.path,
                    available: readyDestination != nil,
                    choosingDisabled: model.snapshot?.storageBusy == true || preparing || model.saving) {
                    destination = MediaSyncStore.chooseFolder(message: "Choose where to save copies from your phone.")?.path ?? destination
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if preparing {
                    ProgressView("Preparing secure connection…").font(.pixfun(12))
                } else if let transfer, transfer.phase == "waiting",
                          let expires = transfer.expiresAt, expires > context.date.timeIntervalSince1970,
                          let url = transfer.url, let qr = qrImage(url) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 24) {
                            code(qr, expires: expires, now: context.date)
                            steps.frame(minWidth: 230, maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 20) {
                            code(qr, expires: expires, now: context.date).frame(maxWidth: .infinity)
                            steps
                        }
                    }
                } else if let transfer, ["connected", "uploading", "complete"].contains(transfer.phase) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(transfer.phase == "complete" ? "Transfer complete" : transfer.phase == "uploading" ? "Receiving your files" : "Phone connected",
                              systemImage: transfer.phase == "complete" ? "checkmark.circle" : "iphone")
                            .font(.pixfun(16, semibold: true)).foregroundStyle(Color.pixfunGoldText)
                        if transfer.phase == "connected" {
                            Text("On your phone, tap Choose photos & videos, then Start transfer.")
                                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                        } else {
                            Text("\(transfer.completed ?? 0) imported · \(transfer.skipped ?? 0) already imported")
                                .font(.pixfun(13))
                            if transfer.phase == "uploading" {
                                ProgressView(value: Double(transfer.processed), total: Double(max(1, transfer.total ?? 1)))
                                Text("\(transfer.processed) of \(transfer.total ?? 0) files verified")
                                    .font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                                if let bytes = transfer.bytes, let total = transfer.totalBytes, total > 0 {
                                    Text("Current file: \(SyncFormat.bytes(bytes)) / \(SyncFormat.bytes(total))")
                                        .font(.pixfun(11)).monospacedDigit().foregroundStyle(Color.pixfunMuted)
                                }
                            } else {
                                Text("Copies are saved in Media. Analysis continues on your Mac. Scan a new code for your next batch.")
                                    .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            }
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.pixfunBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                } else if readyDestination == nil {
                    Text("Choose a connected save location to show your import code.")
                        .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                } else if model.error == nil && transfer?.error == nil {
                    if transfer?.phase == "expired" {
                        Text("This code or session expired. Create a new code.")
                            .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    } else if cancelled || transfer?.phase == "cancelled" {
                        Text("Import cancelled. Completed files are kept.")
                            .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    }
                }
            }
            if let error = model.error ?? transfer?.error {
                Text(error).font(.pixfun(12)).foregroundStyle(Color.pixfunGoldText).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if transfer?.phase != "uploading", transfer?.phase != "connected" {
                    Button(LocalizedStringKey(transfer?.phase == "complete" ? "Import another batch" : "New code")) { preparePairing(retry: true) }
                        .buttonStyle(PixfunButtonStyle(kind: .secondary)).disabled(readyDestination == nil || preparing || model.saving)
                }
                if let transfer, ["waiting", "connected", "uploading"].contains(transfer.phase) {
                    Button("Cancel import") {
                        cancelled = true
                        Task { await model.perform(["action": "phoneImportCancel"]) }
                    }.buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(model.saving)
                }
            }
        }
        .onAppear { preparePairing() }
        .onChange(of: readyDestination) { _ in preparePairing() }
        .onChange(of: model.saving) { saving in if !saving { preparePairing() } }
    }
    private var steps: some View {
        VStack(alignment: .leading, spacing: 18) {
            step(1, "Scan with your phone camera", "Connect both devices to the same Wi-Fi, then scan to open the import page. No app to install.")
            step(2, "Choose photos & videos", "Only selected files are imported—not your whole photo library.")
            step(3, "Start transfer", "Keep the phone page open and Pixfun running until the transfer completes. Verified copies appear in Media.")
        }
    }
    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(number)).font(.pixfun(11, semibold: true)).foregroundStyle(Color.pixfunGoldText)
                .frame(width: 24, height: 24).background(Color.pixfunGold.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(title)).font(.pixfun(13, semibold: true))
                Text(detail).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func code(_ qr: NSImage, expires: Double, now: Date) -> some View {
        let remaining = max(0, Int(expires - now.timeIntervalSince1970))
        return VStack(spacing: 10) {
            Image(nsImage: qr).interpolation(.none).frame(width: 220, height: 220).padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Temporary QR code. Scan with your phone camera.")
            Text(String(format: "Code expires in %d:%02d", remaining / 60, remaining % 60))
                .font(.pixfun(11)).monospacedDigit().foregroundStyle(Color.pixfunMuted)
            Text("Keep this code private").font(.pixfun(10)).foregroundStyle(Color.pixfunSubtle)
        }.fixedSize(horizontal: true, vertical: false)
    }
    @MainActor private func preparePairing(retry: Bool = false) {
#if !PIXFUN_LAYOUT_TEST
        guard let selected = readyDestination, !preparing, !model.saving else { return }
        guard retry || (!cancelled && attemptedDestination != selected) else { return }
        attemptedDestination = selected
        if !retry, destination == nil || destination == model.snapshot?.working?.path,
           let transfer, transfer.phase != "idle" { return }
        cancelled = false; preparing = true
        Task { @MainActor in
            var payload: [String: Any] = ["action": "phoneImportBegin"]
            if let destination { payload["workingPath"] = destination }
            await model.perform(payload)
            preparing = false
        }
#endif
    }
    private func qrImage(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, floor(220 / output.extent.width))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
