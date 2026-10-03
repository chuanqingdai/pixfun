import SwiftUI

struct SkillsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var selected: CreatorSkill?
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                if let skill = selected {
                    HStack {
                        Button { selected = nil } label: { Label("All skills", systemImage: "chevron.left") }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                        Spacer()
                        Button(skill.actionTitle ?? "Use skill") { store.use(skill) }.buttonStyle(PixfunButtonStyle(kind: .primary))
                    }
                    PageHeading(title: skill.title, subtitle: skill.applicability ?? skill.copy)
                    if let notFor = skill.notFor {
                        Text("Not for: \(notFor)").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    }
                    HStack(alignment: .top, spacing: 30) {
                        skillImage(skill).aspectRatio(16.0 / 9.0, contentMode: .fit).frame(width: 290).clipShape(RoundedRectangle(cornerRadius: 12))
                        section("For creators", skill.value)
                    }
                    if let note = skill.capabilityNote {
                        Label(note, systemImage: "info.circle")
                            .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.pixfunGold.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Divider()
                    Text("Story framework").font(.pixfun(18, semibold: true))
                    ForEach(Array(skill.structure.enumerated()), id: \.offset) { index, title in
                        HStack(alignment: .top, spacing: 18) {
                            Text(String(format: "%02d", index + 1)).font(.title3.monospacedDigit()).foregroundStyle(Color.pixfunGold)
                            VStack(alignment: .leading, spacing: 8) { Text(title).font(.pixfun(15, semibold: true)); Text(skill.beats[index]).foregroundStyle(Color.pixfunMuted) }
                        }
                    }
                    Divider()
                    if let highlights = skill.highlights {
                        Text("Key principles").font(.pixfun(18, semibold: true))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), alignment: .topLeading)], alignment: .leading, spacing: 24) {
                            ForEach(highlights, id: \.title) { point in section(point.title, point.body) }
                        }
                    } else {
                        HStack(alignment: .top, spacing: 30) { section("Pacing", skill.pacing); section("Sound", skill.sound) }
                        section("Works with", skill.materials.joined(separator: " · "))
                        section("Material strategy", skill.handling.joined(separator: "\n\n"))
                    }
                    section("Keep it honest", skill.avoid)
                    if let cases = skill.materialCases {
                        Divider()
                        Text("Made for your material").font(.pixfun(18, semibold: true))
                        ForEach(cases, id: \.title) { point in section(point.title, point.body) }
                    }
                    if let templates = skill.templates {
                        Divider()
                        Text("Six packaging templates").font(.pixfun(18, semibold: true))
                        Text("Choose one visual language. Adjust the intensity to your material.")
                            .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), alignment: .topLeading)], alignment: .leading, spacing: 22) {
                            ForEach(templates, id: \.title) { point in
                                section(point.title, point.body).padding(18)
                                    .frame(maxHeight: .infinity, alignment: .topLeading)
                                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    if let workflow = skill.workflow {
                        Divider()
                        Text("Nine-step workflow").font(.pixfun(18, semibold: true))
                        ForEach(Array(workflow.enumerated()), id: \.offset) { index, point in
                            HStack(alignment: .top, spacing: 18) {
                                Text(String(format: "%02d", index + 1)).font(.pixfun(15, semibold: true).monospacedDigit()).foregroundStyle(Color.pixfunGold)
                                section(point.title, point.body)
                            }
                        }
                    }
                    section("Example brief", skill.example)
                    if skill.id == "visionflow-travel-director" {
                        section("Available in Agent", "Route-led storytelling, complete actions, content-led length and source coverage checks. Create a story plan or a video rough cut with original sound, then refine it in the conversation.")
                        section("Not connected yet", "Licensed music and mixing, photo motion, chapter graphics, location labels and full-film audiovisual review. Rough cuts are not the full specification’s finished-film delivery.")
                    }
                    if let url = skill.specificationURL {
                        HStack {
                            Button { NSWorkspace.shared.open(url) } label: {
                                Label("Full skill · v\(skill.version ?? "1")", systemImage: "doc.text")
                            }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                            Spacer()
                            Text("Your brief overrides the skill’s defaults.")
                                .font(.pixfun(12)).foregroundStyle(Color.pixfunSubtle)
                        }
                    }
                } else {
                    PageHeading(title: "Creator skills", subtitle: "Editing strategies for your kind of story.")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 22)], spacing: 24) {
                        ForEach(store.skills) { skill in
                            Button { selected = skill } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    skillImage(skill).aspectRatio(16.0 / 9.0, contentMode: .fit).clipped()
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(skill.title).font(.pixfun(18, semibold: true))
                                        Text(skill.copy).font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                                            .fixedSize(horizontal: false, vertical: true).frame(minHeight: 50, alignment: .topLeading)
                                    }.padding(18)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(PixfunCardStyle())
                        }
                    }
                }
            }.padding(32).frame(maxWidth: 1150).frame(maxWidth: .infinity)
        }.navigationTitle("Skills")
    }
    func section(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.pixfun(16, semibold: true)); Text(content).foregroundStyle(Color.pixfunMuted).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder func skillImage(_ skill: CreatorSkill) -> some View {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("SkillCovers/\(skill.image).jpg"), let image = NSImage(contentsOf: url) {
            GeometryReader { proxy in
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 48).allowsHitTesting(false)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.23), lineWidth: 0.5)
                            .padding(8).allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        ZStack {
                            Path { path in
                                path.move(to: CGPoint(x: 3, y: 14))
                                path.addCurve(to: CGPoint(x: 53, y: 5), control1: CGPoint(x: 21, y: 17), control2: CGPoint(x: 32, y: 0))
                            }.stroke(Color.pixfunGold, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            Circle().fill(Color.pixfunGold).frame(width: 4, height: 4).position(x: 3, y: 14)
                            Circle().fill(Color.pixfunGold).frame(width: 4, height: 4).position(x: 53, y: 5)
                        }.frame(width: 56, height: 20).padding(14).allowsHitTesting(false).accessibilityHidden(true)
                    }
            }
        } else { Rectangle().fill(.white.opacity(0.05)).overlay(Image(systemName: "wand.and.stars").font(.largeTitle)) }
    }
}
