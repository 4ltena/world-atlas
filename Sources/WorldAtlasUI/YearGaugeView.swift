import SwiftUI
import WorldAtlasCore

/// 年表の上に置く一行（設計書 8.5）。暦、年の読み、合わせる、全体、色帯、畳む記号。
struct YearGaugeView: View {
    @Bindable var store: VaultStore
    /// 幅は年表の側が持っているので、当てはめは呼び出し側へ渡す。
    var onFit: () -> Void
    var onWhole: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 暦はポップアップで選ぶ（設計書 8.5）。選んだ暦は vault ごとに覚えるので、
            // 束縛を直に繋がず setCalendar を通す。
            Picker("", selection: Binding(get: { store.calendarName },
                                          set: { store.setCalendar($0) })) {
                ForEach(store.snapshot.world.calendars, id: \.name) { c in
                    Text(c.name).tag(c.name)
                }
            }
            .labelsHidden()
            .fixedSize()

            // 掴んでいる間はここだけが追随する（設計書 8.6）。木と本文は離すまで動かない。
            Text(store.calendar.format(store.displayedYear))
                .font(.system(.body, design: .default))
                .monospacedDigit()

            if store.calendar.name != store.snapshot.world.baseCalendar {
                // 基準暦以外を選んだときだけ、基準暦の年を小さく併記する（設計書 6 節）。
                // **数を素で埋め込まない。**0 以下は「前 n 年」であり、それは format が知っている。
                Text("（\(store.baseCalendar.format(store.displayedYear))）")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }

            Spacer()

            Button("合わせる", action: onFit)
            Button("全体", action: onWhole)
            Toggle("支配の色帯", isOn: $store.showsRuleStripes)
                .toggleStyle(.checkbox)

            Button {
                store.timelineCollapsed.toggle()
            } label: {
                Image(systemName: store.timelineCollapsed ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.plain)
            .help(store.timelineCollapsed ? "年表を出す" : "年表を畳む")
            .accessibilityLabel(store.timelineCollapsed ? "年表を出す" : "年表を畳む")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Palette.sidebar)
    }
}
