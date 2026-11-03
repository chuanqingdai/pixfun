import SwiftUI

/// In-memory UI fixture: no service, database, real media or persisted drafts.
@main struct StorySpeechSmokeApp: App {
    var body: some Scene {
        WindowGroup("语句辅助裁剪 · 隔离测试") {
            SpeechFixture().preferredColorScheme(.dark).environment(\.locale, Locale(identifier: "zh-Hans"))
                .frame(width: 340, height: 230)
        }.defaultSize(width: 340, height: 230)
    }
}

struct SpeechFixture: View {
    @State private var start = 1.4
    @State private var end = 3.6
    @State private var previous: (Double, Double)?
    let guide = StorySpeechGuide(mediaId: "fixture", revision: "source", evidenceRevision: "speech", kind: "asr", boundaries: [
        .init(time: 1, edge: "start", text: "我们沿着湖边的小路前行。"), .init(time: 4, edge: "end", text: "我们沿着湖边的小路前行。")])
    var shot: AgentShot { .init(id: "fixture", mediaId: "fixture", start: start, end: end, label: "Fixture", reason: "", locked: false) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("湖边行走 · 测试片段").font(.pixfun(13, semibold: true))
            HStack {
                Text("In")
                StoryTimeField(value: start, label: "Source in point", valid: { $0 >= 0 && $0 <= end - 0.25 }) { change($0, true) }
                Spacer()
                Text("Out")
                StoryTimeField(value: end, label: "Source out point", valid: { $0 >= start + 0.25 && $0 <= 10 }) { change($0, false) }
            }
            StorySpeechHints(kind: guide.kind, inPoint: guide.nearby(shot, leading: true, sourceDuration: 10), outPoint: guide.nearby(shot, leading: false, sourceDuration: 10), disabled: false) { point, leading in change(point.time, leading) }
            Button("Undo") {
                if let previous { start = previous.0; end = previous.1; self.previous = nil }
            }.disabled(previous == nil)
            Text("仅使用内存中的测试转写，不修改实际项目。").font(.pixfun(10))
            Spacer(minLength: 0)
        }.font(.pixfun(11)).foregroundStyle(Color.pixfunMuted).padding(16).background(Color.pixfunStoryCard)
    }
    func change(_ time: Double, _ leading: Bool) {
        previous = (start, end)
        if leading { start = time } else { end = time }
    }
}
