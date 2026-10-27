import SwiftUI

/// A presentation of the existing persisted workflow, not a second Agent or job queue.
struct MapCreationPanel: View {
    @EnvironmentObject var store: WorkspaceStore
    let run: AgentRun
    var selectedIDs: Set<String> = []
    private var selectedID: String? { selectedIDs.count == 1 ? selectedIDs.first : nil }
    var onSelect: (String) -> Void
    var onAdjustLocation: (String) -> Void
    @State private var adjustingID: String?
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var editingCoordinates = false
    @State private var materialsExpanded = false
    @State private var shotsExpanded = true
    private var reviewingTrip: Bool { run.status == "clarify" && run.clarificationKind == "trip_confirmation" }
    private var locked: Bool { store.saving || store.agentActionPending || store.agentRuns.contains { $0.busy && $0.id != run.id } }
    private var entries: [AgentTripEntry] { run.tripConfirmation?.entries ?? [] }
    private var selectedEntry: AgentTripEntry? { entries.first { $0.mediaId == selectedID } }
    private var story: AgentStoryExecution? {
        run.storyExecution?.matches(version: run.version, shots: run.timeline) == true ? run.storyExecution : nil
    }
    private var showsStory: Bool {
        !run.timeline.isEmpty && (!run.busy || ["render", "finishing", "verify"].contains(run.stage))
    }
    private var pastAnalysis: Bool {
        run.tripConfirmation != nil || ["plan", "render", "finishing", "verify"].contains(run.stage)
    }
    private var title: String {
        if run.status == "failed" { return "创作未完成" }
        if ["cancelled", "interrupted"].contains(run.status) { return "创作已暂停" }
        if reviewingTrip || run.needsRouteConfirmation { return "确认行程" }
        if run.awaitingScriptConfirmation { return "确认编排策略" }
        if run.preview != nil { return "视频已生成" }
        return ["plan", "trip"].contains(run.stage) ? "编排故事" : ["render", "finishing", "verify"].contains(run.stage) ? "生成预览" : "分析素材"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    if run.busy {
                        AgentActivityView(run: run, prominent: true)
                        if run.analyzingMaterials {
                            let progress = run.analysisMaterials(in: store.items)
                            Text("已完成 \(progress.filter(\.finished).count)/\(run.mediaIds?.count ?? progress.count)")
                                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                        }
                    } else {
                        Text(title).font(.pixfun(18, semibold: true))
                    }
                    if showsStory {
                        Text("\(run.timeline.count) 个镜头 · \(String(format: "%.1f", run.timeline.reduce(0) { $0 + $1.end - $1.start })) 秒 · \(run.aspect)")
                            .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    }
                    if ["failed", "cancelled", "interrupted"].contains(run.status) {
                        if run.status == "failed" {
                            Text(LocalizedStringKey(run.conciseFailure)).font(.pixfun(13))
                            if let detail = run.failureDetail { Text(detail).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted) }
                        } else {
                            Text("任务已暂停，已完成的结果会保留。").font(.pixfun(13))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Button {
                    store.mapCreationHidden = true
                } label: { Image(systemName: "xmark").frame(width: 28, height: 28).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("返回地图浏览，进度会保留").accessibilityLabel("收起创作")
            }.padding(16)
                .background(Color.pixfunRaised)
                .accessibilityIdentifier("map-creation-status")
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if reviewingTrip {
                            Text("点击“调整位置”，在地图上拖动素材点。")
                                .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                            tripList
                        } else {
                            if showsStory {
                                storyPlan
                            } else if pastAnalysis {
                                strategyOverview
                            }
                            if run.tripConfirmation?.status == "confirmed" {
                                DisclosureGroup(run.tripConfirmation?.useLocations == false ? "已确认 · 不使用位置" : "已确认行程") { tripList.padding(.top, 10) }
                                    .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            }
                            if pastAnalysis {
                                DisclosureGroup("素材分析 · \(run.materialCards(in: store.items).count) 个素材", isExpanded: $materialsExpanded) {
                                    materialList.padding(.top, 12)
                                }.font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            } else {
                                materialList
                            }
                            if run.status == "clarify" && !reviewingTrip {
                                Text(run.question).font(.pixfun(13)).textSelection(.enabled)
                            }
                        }
                        if let preview = run.preview {
                            AgentVideoMessage(artifact: preview, aspect: run.aspect, editorProjectID: run.projectId)
                        }
                    }.padding(16)
                }
                .onChange(of: selectedIDs) { ids in
                    if selectedID != adjustingID { editingCoordinates = false; adjustingID = nil }
                    let id = entries.first { ids.contains($0.mediaId) }?.mediaId
                        ?? run.materialCards(in: store.items).first { ids.contains($0.id) }?.id
                    guard let id else { return }
                    let target: String
                    if reviewingTrip { target = "trip-\(id)" }
                    else if showsStory, let shot = run.timeline.first(where: { ids.contains($0.mediaId) }) {
                        shotsExpanded = true
                        target = "shot-\(shot.id)"
                    } else {
                        materialsExpanded = true
                        target = "material-\(id)"
                    }
                    // Wait for the disclosure's content to enter the view tree.
                    DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
                }
            }
            Divider()
            HStack(alignment: .center, spacing: 12) {
                if !run.busy {
                    actions
                } else if store.agentActionPending {
                    ProgressView().controlSize(.small)
                    Text("正在处理…").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                }
                Spacer(minLength: 0)
                if run.busy {
                    Button {
                        store.agentAction("stop", run: run)
                    } label: {
                        Label("停止", systemImage: "stop.circle").font(.pixfun(13))
                            .frame(minWidth: 64, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(locked)
                        .accessibilityIdentifier("map-creation-stop")
                }
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(16).accessibilityIdentifier("map-creation-actions")
        }
        .frame(maxHeight: .infinity)
        .background(Color.pixfunSurface)
    }

    private var tripList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    tripRow(entry)
                    if reviewingTrip && selectedID == entry.mediaId {
                        coordinateEditor(entry)
                    }
                }.id("trip-\(entry.mediaId)")
            }
        }
    }

    private func tripRow(_ entry: AgentTripEntry) -> some View {
        let item = store.items.first { $0.id == entry.mediaId }
        let selected = selectedIDs.contains(entry.mediaId)
        return HStack(alignment: .center, spacing: 8) {
            Button {
                if let item { store.openMedia(item) }
            } label: {
                ServiceImage(path: item?.cover).frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(alignment: .bottomLeading) {
                        Text("#\(entry.number)").font(.pixfun(10, semibold: true))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.pixfunBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                    }
            }.buttonStyle(.plain).disabled(item == nil).help("查看素材详情")
                .accessibilityLabel("查看 \(entry.name) 详情")
            Button { onSelect(entry.mediaId) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.place.isEmpty ? (entry.correction != nil ? "位置已调整" : "地点待确认") : entry.place)
                        .font(.pixfun(12, semibold: true)).lineLimit(2)
                    Text(entry.name).font(.pixfun(11)).foregroundStyle(Color.pixfunMuted).lineLimit(1).truncationMode(.middle)
                    Text(entry.capturedAt.isEmpty ? "时间未记录" : String(entry.capturedAt.prefix(16)).replacingOccurrences(of: "T", with: " "))
                        .font(.pixfun(10)).foregroundStyle(Color.pixfunMuted)
                    if entry.location == nil {
                        Text("无定位").font(.pixfun(10)).foregroundStyle(Color.pixfunMuted)
                    } else if entry.correction != nil {
                        Text("已调整").font(.pixfun(10)).foregroundStyle(Color.pixfunGoldText)
                    }
                }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("在地图中定位")
            if reviewingTrip {
                Button {
                    adjustingID = entry.mediaId
                    latitude = entry.location.map { String(format: "%.6f", $0.latitude) } ?? ""
                    longitude = entry.location.map { String(format: "%.6f", $0.longitude) } ?? ""
                    editingCoordinates = entry.location == nil
                    onAdjustLocation(entry.mediaId)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 15))
                        Text("调整位置").font(.pixfun(10))
                    }.frame(width: 48, height: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(Color.pixfunGoldText).disabled(locked)
                    .accessibilityLabel("调整 \(entry.name) 的位置")
                    .accessibilityIdentifier("map-adjust-location-\(entry.mediaId)")
            }
        }.padding(8)
            .background(selected ? Color.pixfunBrandSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.pixfunGold : .clear, lineWidth: 1))
            .accessibilityValue(selected ? "已在地图中选中" : "")
    }

    private var materialList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(run.materialCards(in: store.items)) { card in
                VStack(alignment: .leading, spacing: 5) {
                    sourceRow(card.id, title: card.title, subtitle: store.language.text(card.progress?.label ?? "Waiting to analyze"))
                    if selectedIDs.contains(card.id) && !card.summary.isEmpty {
                        Text(card.summary).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            .lineSpacing(3).lineLimit(3).padding(.horizontal, 6)
                    }
                }.id("material-\(card.id)")
            }
        }
    }

    private var strategyOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("故事怎么讲").font(.pixfun(15, semibold: true))
            if let summary = run.arrangementSummary {
                Text(summary).font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                    .lineSpacing(4).lineLimit(3).truncationMode(.tail).textSelection(.enabled)
            } else {
                Text(run.busy ? "正在根据高光片段组织故事，完成后请确认编排策略。" : "尚未生成编排策略，可重试后继续。")
                    .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted).lineSpacing(4)
            }
            if let notice = story?.chapterNotice {
                Text(notice).font(.pixfun(12)).foregroundStyle(Color.pixfunGoldText)
            }
            if let outline = story?.outline, !outline.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(outline.enumerated()), id: \.element.id) { index, chapter in
                        chapterStrategy(chapter, index: index, count: outline.count)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chapterStrategy(_ chapter: AgentStoryExecution.Chapter, index: Int, count: Int) -> some View {
        let shots = run.timeline.filter { chapter.shotIds.contains($0.id) }
        let duration = shots.reduce(0) { $0 + $1.end - $1.start }
        let stage = count == 1 ? "全片" : index == 0 ? "开场" : index == count - 1 ? "收尾" : "第\(index + 1)段"
        return HStack(alignment: .top, spacing: 12) {
            Text(stage).font(.pixfun(11, semibold: true)).foregroundStyle(Color.pixfunGoldText)
                .frame(width: 36, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                Text(chapter.title).font(.pixfun(14, semibold: true)).fixedSize(horizontal: false, vertical: true)
                Text("\(shots.count) 个镜头 · \(String(format: "%.1f", duration)) 秒")
                    .font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                if !chapter.intent.isEmpty {
                    Text(chapter.intent).font(.pixfun(13)).lineSpacing(4).textSelection(.enabled)
                }
                if !chapter.bridge.isEmpty {
                    Text("衔接：\(chapter.bridge)").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                        .lineSpacing(4).textSelection(.enabled)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }

    private var storyPlan: some View {
        VStack(alignment: .leading, spacing: 14) {
            strategyOverview
            Divider().padding(.vertical, 4)
            DisclosureGroup("分镜安排", isExpanded: $shotsExpanded) {
                shotList.padding(.top, 12)
            }.font(.pixfun(13, semibold: true))
            if run.currentScriptConfirmed { Label("编排策略已确认", systemImage: "checkmark.circle.fill").font(.pixfun(12)).foregroundStyle(Color.pixfunGoldText) }
        }
    }

    private var shotList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(run.timeline.enumerated()), id: \.element.id) { index, shot in
                if let chapter = story?.outline?.first(where: { $0.shotIds.first == shot.id }) {
                    Text(chapter.title).font(.pixfun(14, semibold: true)).padding(.top, 6)
                }
                VStack(alignment: .leading, spacing: 7) {
                    sourceRow(shot.mediaId, title: "\(index + 1). \(shot.label)",
                              subtitle: "\(String(format: "%.1f", shot.start))–\(String(format: "%.1f", shot.end)) 秒")
                    if !shot.reason.isEmpty {
                        Text(shot.reason).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            .lineSpacing(3).textSelection(.enabled).padding(.horizontal, 6)
                    }
                }.padding(.vertical, 6).id("shot-\(shot.id)")
            }
        }
    }

    private func sourceRow(_ id: String, title: String, subtitle: String) -> some View {
        let item = store.items.first { $0.id == id }
        return HStack(alignment: .top, spacing: 10) {
            Button {
                if let item { store.openMedia(item) }
            } label: {
                ServiceImage(path: item?.cover).frame(width: 64, height: 44).clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selectedIDs.contains(id) ? Color.pixfunGold : .clear, lineWidth: 2))
            }.buttonStyle(.plain).disabled(item == nil).help("查看素材详情").accessibilityLabel("查看素材详情")
            Button { onSelect(id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.pixfun(13, semibold: true)).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.pixfun(11)).foregroundStyle(Color.pixfunMuted).lineLimit(2)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("在地图中定位")
        }
        .padding(6)
        .background(selectedIDs.contains(id) ? Color.pixfunBrandSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selectedIDs.contains(id) ? Color.pixfunGold : .clear, lineWidth: 1))
        .accessibilityValue(selectedIDs.contains(id) ? "已在地图中选中" : "")
    }

    private func coordinateEditor(_ entry: AgentTripEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(editingCoordinates ? "收起坐标编辑" : "输入坐标或恢复原始位置") {
                latitude = entry.location.map { String(format: "%.6f", $0.latitude) } ?? ""
                longitude = entry.location.map { String(format: "%.6f", $0.longitude) } ?? ""
                editingCoordinates.toggle()
            }.buttonStyle(.plain).font(.pixfun(12)).foregroundStyle(Color.pixfunGoldText)
            if editingCoordinates {
                Text(entry.name).font(.pixfun(12)).lineLimit(1)
                TextField("纬度（WGS84）", text: $latitude, prompt: PixfunTypography.placeholder("纬度（WGS84）"))
                TextField("经度（WGS84）", text: $longitude, prompt: PixfunTypography.placeholder("经度（WGS84）"))
                HStack {
                    Button("应用坐标") {
                        if let lat = Double(latitude), let lon = Double(longitude) {
                            store.moveMapTripPoint(run, mediaID: entry.mediaId, latitude: lat, longitude: lon)
                        }
                    }.disabled(Double(latitude).map { !$0.isFinite || abs($0) > 90 } ?? true
                               || (Double(longitude).map { !$0.isFinite || abs($0) > 180 } ?? true))
                    Button("恢复原始位置") { store.moveMapTripPoint(run, mediaID: entry.mediaId, reset: true) }
                        .disabled(entry.originalLocation == nil)
                }.font(.pixfun(12))
                Text("调整只用于本应用，不修改原文件。").font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
            }
        }.disabled(locked)
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.agentActionPending || store.saving {
                HStack { ProgressView().controlSize(.small); Text("正在保存…").font(.pixfun(12)) }
            }
            if reviewingTrip {
                Button("确认行程，编排故事") { store.agentAction("confirm_trip", run: run) }
                    .buttonStyle(PixfunButtonStyle(kind: .primary))
            } else if run.awaitingScriptConfirmation {
                Button { store.agentAction("approve", run: run) } label: {
                    Text(run.needsRouteConfirmation ? "先确认行程" : "确认策略，生成预览")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(PixfunButtonStyle(kind: .primary))
            } else if ["failed", "cancelled", "interrupted"].contains(run.status) {
                Button("重试") { store.agentAction("retry", run: run) }.buttonStyle(PixfunButtonStyle(kind: .primary))
            } else if run.preview != nil {
                Button("打开编辑器") { store.openEditor(run.projectId) }.buttonStyle(PixfunButtonStyle(kind: .primary))
            } else if run.canUseVideosOnly {
                Button("使用可用素材继续") { store.agentAction(run.clarificationKind == "visual_only" ? "use_visuals" : "use_videos", run: run) }
            } else if run.status == "clarify" {
                Text("当前请求需要补充信息，可返回地图重新选择素材。").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
            }
        }.disabled(locked).frame(maxWidth: .infinity, alignment: .leading)
    }
}
