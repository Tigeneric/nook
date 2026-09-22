import SwiftUI
import NookCore

/// The settings window: launch, hot key, floor and sheet.
struct SettingsView: View {
    @Bindable var preferences: Preferences
    let loginItem: LoginItem
    let hotKeys: HotKeyController
    let store: ScheduleStore
    let focus: SettingsFocus

    @State private var input = ""
    @State private var nameInput = ""
    @State private var failed = false
    @State private var recording = false
    @FocusState private var focused: SettingsFocus.Field?

    /// Shown in the corner of the settings window: “which build do you have?”
    /// should be answerable without digging through Finder. An SPM run has no
    /// Info.plist, hence the fallback.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        guard let marketing = info?["CFBundleShortVersionString"] as? String else { return "Nook dev" }
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Nook \(marketing) (\(build))"
    }

    private var floors: [Int] {
        Array(Set(Space.all.map(\.floor))).sorted()
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.set($0) }
                ))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let failure = loginItem.failure {
                        Text("Couldn’t change the login item: \(failure)")
                            .foregroundStyle(.red)
                    }
                    Text("Nook lives in the menu bar and answers a hotkey; without this it has to be started by hand after every restart.")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(HotKeyCombo.presets, id: \.self) { preset in
                    hotKeyChoice(preset, label: Text(verbatim: preset.description))
                }
                hotKeyChoice(nil, label: Text("Off"))
                customHotKeyChoice
            } header: {
                Text("Show the overlay with")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let rejected = hotKeys.rejected {
                        Text("\(rejected.description) is taken by another app — pick another one")
                            .foregroundStyle(.red)
                    }
                    Text("A combination needs ⌘, ⌥, ⌃ or ⇧: a bare key would be taken away from every other app. Function keys may stand alone. Whatever is set here, the overlay is also reachable from the menu bar.")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker(selection: $preferences.floor) {
                    Text("All floors").tag(Int?.none)
                    ForEach(floors, id: \.self) { floor in
                        Text("Floor \(String(floor))").tag(Int?.some(floor))
                    }
                } label: {
                    Text("Search on")
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Between floors is a walk: an answer on the other floor is often no answer at all. A space named in the query is still shown, whichever floor it is on.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                TextField("Link to the sheet", text: $input, prompt: Text(verbatim: "https://docs.google.com/spreadsheets/d/…"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)

                HStack {
                    Button("Save", action: save)
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    if preferences.isConfigured {
                        Button("Forget") {
                            preferences.clearSpreadsheet()
                            input = ""
                            failed = false
                            store.reload()
                        }
                    }
                }
            } header: {
                Text("Booking sheet")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if failed {
                        Text("Doesn’t look like a sheet link or ID")
                            .foregroundStyle(.red)
                    } else if let id = preferences.spreadsheetID {
                        Text("Current: \(id)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not set yet — the overlay has nothing to read")
                            .foregroundStyle(.secondary)
                    }
                    Text("Paste the whole link from the browser. The sheet has to be readable by link: Nook does no authorization.")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                TextField("Your name in the sheet", text: $nameInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .bookingName)
            } header: {
                Text("Your bookings")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    nameCheck
                    Text("With this set, the overlay opens on your own nearest bookings. A cell holds nothing but a name, so this is the only way to tell yours from everyone else’s. Write it as it stands in the sheet: case, accents and spaces are disregarded, so “AnaPetrovic” and “Ana Petrović” are one name — everything else has to match.")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(verbatim: Self.version)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
                .padding(.bottom, 8)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear {
            input = preferences.spreadsheetID ?? ""
            nameInput = preferences.bookingName ?? ""
        }
        .onChange(of: input) { _, _ in failed = false }
        // Saved as it is typed: there is nothing to validate, so a Save button
        // would only be a way to lose the name by closing the window.
        .onChange(of: nameInput) { _, new in preferences.setBookingName(new) }
        // The ⓘ in the overlay asks for this field by name.
        .onChange(of: focus.token) { _, _ in focused = focus.field }
    }

    // MARK: - Is this name in the sheet at all

    /// The answer to the question the field cannot answer on its own: a
    /// misspelled name matches nothing, and that looks exactly like an empty
    /// week. Counted against the **whole** sheet, both floors and the past
    /// included — the question is “is this name written here”, not “where do I
    /// sit next”, and the floor filter would make a correct name look wrong.
    ///
    /// The schedule is fetched once per opening of this window, and matching
    /// against it is plain local arithmetic — so the answer follows the
    /// keystrokes without a request behind each one.
    @ViewBuilder
    private var nameCheck: some View {
        let name = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            switch store.state {
            case .idle, .loading:
                Text("Checking against the sheet…").foregroundStyle(.secondary)
            case .loaded(let schedule):
                let found = Agenda.all(for: name, in: schedule, spaces: schedule.spaces)
                if found.isEmpty {
                    // Matching nothing is either a typo or a person who has not
                    // booked yet, and the sheet alone cannot tell them apart —
                    // so it does not pretend to. A near-miss sitting in the
                    // sheet is the one piece of evidence there is.
                    if let similar = Agenda.closestName(to: name, in: schedule) {
                        Text("Nothing in the sheet under this name. Did you mean “\(similar)”?")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Nothing in the sheet under this name yet — that is how it looks until your first booking")
                            .foregroundStyle(.secondary)
                    }
                } else if let next = nextBooking(for: name, in: schedule) {
                    Text("Found in \(String(found.count)) bookings, the next one \(next)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Found in \(String(found.count)) bookings, none of them ahead")
                        .foregroundStyle(.secondary)
                }
            case .notConfigured, .failed:
                // The sheet section above is already saying what is wrong with
                // the sheet; repeating it here would be noise.
                EmptyView()
            }
        }
    }

    /// `C1 · 22/09 19:00` — enough to recognise it in the sheet.
    private func nextBooking(for name: String, in schedule: Schedule) -> String? {
        let now = Date()
        guard let booking = Agenda.upcoming(
            for: name,
            in: schedule,
            spaces: schedule.spaces,
            today: CalendarDate(now),
            now: Self.timeOfDay(of: now),
            limit: 1
        ).first else { return nil }
        return String(
            format: "%@ · %02d/%02d %@",
            booking.space.id, booking.date.day, booking.date.month, booking.start.description
        )
    }

    private static func timeOfDay(of date: Date) -> TimeOfDay {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    private func save() {
        failed = !preferences.setSpreadsheet(input)
        if !failed {
            input = preferences.spreadsheetID ?? ""
            store.reload()
        }
    }

    // MARK: - Hot key

    /// One line of the radio list. `nil` is the “off” line.
    ///
    /// Built by hand rather than with `Picker(.radioGroup)`: the custom line
    /// carries a button, and a picker row holds nothing but its label.
    private func hotKeyChoice(_ combo: HotKeyCombo?, label: Text) -> some View {
        Button {
            recording = false
            preferences.setHotKey(combo)
            hotKeys.apply()
        } label: {
            HStack(spacing: 8) {
                radio(on: !isCustom && preferences.hotKey == combo)
                label
                Spacer()
            }
            // Without this the row reacts only where the text is.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var customHotKeyChoice: some View {
        HStack(spacing: 8) {
            radio(on: isCustom)
            if let combo = preferences.hotKey, isCustom {
                Text(verbatim: combo.description)
            } else {
                Text("Something else").foregroundStyle(.secondary)
            }
            Spacer()
            if recording {
                Text("Press a combination")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // One point rather than none: a view of zero size is not put
                // in the window, and one that is not in the window cannot
                // become first responder.
                HotKeyRecorder { combo in
                    recording = false
                    guard let combo else { return }
                    preferences.setHotKey(combo)
                    hotKeys.apply()
                }
                .frame(width: 1, height: 1)
            } else {
                Button("Record…") { recording = true }
            }
        }
    }

    /// The setting is something a person recorded — not a preset, not off.
    private var isCustom: Bool {
        guard let combo = preferences.hotKey else { return false }
        return !HotKeyCombo.presets.contains(combo)
    }

    private func radio(on: Bool) -> some View {
        Image(systemName: on ? "largecircle.fill.circle" : "circle")
            .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .imageScale(.medium)
    }
}
