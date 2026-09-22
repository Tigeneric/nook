import SwiftUI
import NookCore

/// The contents of the overlay.
///
/// **A placeholder.** There is no calendar grid here yet: it has to be built
/// in one separate pass. For now the answer is text — a cheap test of whether
/// the thing is worth building, and an end-to-end check of the chain
/// load → model → search.
///
/// The strings are keys of `Localizable.xcstrings`: the English text is the
/// key, so an untranslated language falls back to English on its own.
struct OverlayView: View {
    let store: ScheduleStore
    let preferences: Preferences
    let today: CalendarDate
    let now: TimeOfDay
    let onOpen: (Space, Query, _ copyName: Bool) -> BookingOpenResult
    let onClose: () -> Void
    let onSettings: () -> Void
    let onResize: (CGSize) -> Void

    @State private var text: String
    @State private var hoveringSettings = false
    /// Which of the listed bookings the arrows have walked to, if any.
    ///
    /// Nothing is selected when the overlay opens: ⏎ would then lead into the
    /// browser without anybody having chosen anything.
    @State private var selection: Int?
    /// ⏎ found the clipboard impossible to put back, so nothing was copied and
    /// nothing opened. The line below says so, and the next ⏎ goes ahead
    /// without the copy — the decision to lose the shortcut rather than the
    /// clipboard belongs to the person, not to the app.
    @State private var clipboardRefused = false

    init(
        store: ScheduleStore,
        preferences: Preferences,
        today: CalendarDate,
        now: TimeOfDay,
        query: String = "",
        onOpen: @escaping (Space, Query, Bool) -> BookingOpenResult,
        onClose: @escaping () -> Void,
        onSettings: @escaping () -> Void = {},
        onResize: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.store = store
        self.preferences = preferences
        self.today = today
        self.now = now
        self.onOpen = onOpen
        self.onClose = onClose
        self.onSettings = onSettings
        self.onResize = onResize
        _text = State(initialValue: query)
    }

    private var query: Query? {
        QueryParser.parse(text, today: today, now: now)
    }

    /// The hint shown in an empty field. ⇥ turns it into the request itself.
    ///
    /// The time is the nearest slot no earlier than `now`, not a hard-coded
    /// “14:00”: at 15:40 such a hint offered the past, and ⇥ inserted it as
    /// is. Once the grid’s day is over the start of the grid is shown —
    /// there is nothing to offer until morning.
    private var placeholder: String {
        "\(SheetGrid.suggestedStart(after: now)) 45m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .leading) {
                QueryField(
                    text: $text,
                    placeholder: placeholder,
                    // One focus, and it is over the list right now.
                    caretHidden: selection != nil,
                    onArrow: { delta, text, caret in
                        // An empty line has no fragment to edit, which is the
                        // one state where the arrows are free — so there they
                        // walk the listed bookings instead. Returning the line
                        // unchanged reports the key as handled: without that
                        // the field would take it and move the caret.
                        if isBlank(text), !myBookings.isEmpty {
                            moveSelection(by: delta)
                            return (text, caret)
                        }
                        // Cycling runs over the spaces free for this request
                        // rather than all of them: stepping through taken
                        // rooms is pointless.
                        return QueryEdit.adjust(
                            text,
                            caret: caret,
                            by: delta,
                            today: today,
                            spaces: freeSpaces(in: text),
                            // Days: only the ones the sheet holds — there is
                            // nowhere to step beyond its period.
                            dates: store.schedule?.dates ?? []
                        )
                        .map { ($0.text, $0.caret) }
                    },
                    onTab: complete,
                    onSubmit: open,
                    onCancel: onClose
                )
                suggestionGhost
            }
            .frame(minHeight: 30)

            Divider()

            content
                .font(.body)
                .foregroundStyle(.secondary)
                // Otherwise the text takes its ideal width on one line and
                // gets truncated: the panel’s width is fixed, and growth has
                // to go downwards.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: OverlayMetrics.width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: OverlaySizeKey.self, value: geometry.size)
            }
        }
        .onPreferenceChange(OverlaySizeKey.self, perform: onResize)
        // The field catches Esc too; this is for when focus has left it.
        .onExitCommand(perform: onClose)
        // The first character typed puts the arrows back to editing the
        // request, so a selection left over from before would be a highlight
        // nothing acts on.
        .onChange(of: text) { _, new in
            if !isBlank(new) { selection = nil }
        }
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Hint for the next part of the request

    /// What ⇥ will add next. Shown in grey right after the typed text, the
    /// way a shell does it: what is offered is visible, and so is the fact
    /// that it has not been entered yet.
    private var suggestion: String? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        // Without a schedule nothing is known about free spaces, and naming
        // one would be guessing. The duration still gets suggested, the space
        // does not: an empty list stops the suggestion there.
        let spaces = store.schedule == nil ? [] : freeSpaces(in: text)
        return QueryEdit.suggestion(after: text, today: today, now: now, spaces: spaces)
    }

    @ViewBuilder
    private var suggestionGhost: some View {
        if let suggestion {
            Text(verbatim: suggestion)
                .font(Self.queryFont)
                .foregroundStyle(.quaternary)
                .padding(.leading, Self.width(of: text + " ") + Self.fieldInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    static let queryNSFont = NSFont.preferredFont(forTextStyle: .title1)
    static let queryFont = Font(queryNSFont)

    /// The text field’s own inset — without it the ghost slides left and
    /// sticks to the caret.
    private static let fieldInset: CGFloat = 2

    /// Width of the typed text in the same font the field draws it in —
    /// otherwise the ghost will not sit right next to the caret.
    private static func width(of text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: queryNSFont]).size().width
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .notConfigured:
            VStack(alignment: .leading, spacing: 6) {
                Text("No sheet configured")
                hint(Text("Menu bar → Settings… → paste the link to your booking sheet"))
            }
        case .idle, .loading:
            Text("Reading the sheet…")
        case .failed(let error):
            VStack(alignment: .leading, spacing: 6) {
                error.message.foregroundStyle(.red)
                hint(retryHint)
            }
        case .loaded(let schedule):
            if let query {
                result(query, schedule)
            } else {
                // The rule is separated from the answer by a line, the way the
                // query line is: what the sheet says and what the keyboard can
                // do are two different kinds of statement.
                VStack(alignment: .leading, spacing: 10) {
                    agenda(schedule)
                    Divider()
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Query: “14:00 45m”, “now 30m C2”, “fri 14:00”, “\(exampleDate(schedule)) 11:00 1h”")
                        // The keys mean different things with an empty line, so
                        // the hint says which ones those are. Without it the
                        // arrows over the list are undiscoverable.
                        if myBookings.isEmpty {
                            hint(Text("⇥ — complete the query · ↑↓ — change what the cursor is on · ⏎ — open in the sheet"))
                        } else {
                            hint(Text("⇥ — start a query · ↑↓ — pick a booking · ⏎ — open it in the sheet"))
                        }
                    }
                }
            }
        }
    }

    // MARK: - My own bookings

    /// The person’s own nearest bookings, shown before anything is typed.
    ///
    /// This is what the overlay gets opened for when nothing needs booking:
    /// “when is my next one, and where”. The grid coming later will not make
    /// this redundant — it draws everybody’s day and singles nobody out.
    ///
    /// Three columns held by alignment rather than by frames, as the approved
    /// mockup has them: at this size a border on every row reads as a table,
    /// and there is no table here.
    @ViewBuilder
    private func agenda(_ schedule: Schedule) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // The heading stands in every state, so the block keeps one shape
            // and the panel does not jump in height between showings. An empty
            // state then reads as an answer rather than as a failed load.
            HStack(spacing: 8) {
                hint(Text("Your bookings"))
                if preferences.bookingName == nil {
                    Spacer()
                    settingsButton
                }
            }
            if preferences.bookingName != nil {
                agendaList()
            } else {
                // Names the state, and no more: what to do about it hangs on
                // the ⓘ, which a person who has already set a name never sees.
                Text("Not set up")
            }
        }
    }

    @ViewBuilder
    private func agendaList() -> some View {
        let mine = myBookings
        if mine.isEmpty {
            // Said rather than left blank: an empty space does not tell you
            // whether it is an answer. It is also the common case — the sheet
            // carries bookings on two of its ten dates.
            Text("Nothing planned")
        } else {
            VStack(alignment: .leading, spacing: 1) {
                // Indices rather than the bookings themselves: a booking has
                // no identity in the source — only a name in a cell.
                ForEach(mine.indices, id: \.self) { index in
                    agendaRow(mine[index], selected: index == selection)
                }
            }
        }
    }

    /// The bookings the list shows. One place, because the rows draw it and the
    /// arrows walk it, and the two must not disagree about the order.
    private var myBookings: [Booking] {
        guard let name = preferences.bookingName, let schedule = store.schedule else { return [] }
        return Agenda.upcoming(
            for: name,
            in: schedule,
            spaces: preferences.spaces(from: schedule.spaces),
            today: today,
            now: now
        )
    }

    private func moveSelection(by delta: Int) {
        selection = Agenda.selection(from: selection, by: delta, count: myBookings.count)
    }

    /// The booking ⏎ would open, if the arrows have chosen one.
    private var selectedBooking: Booking? {
        guard isBlank(text), let selection else { return nil }
        let mine = myBookings
        return mine.indices.contains(selection) ? mine[selection] : nil
    }

    /// The only thing in the overlay that is clicked.
    ///
    /// Sits on the right edge of the heading, where the “how soon” column sits
    /// in the rows — the block keeps a single right edge. ⌘, does the same from
    /// the keyboard in any state (`OverlayPanel`), which is what keeps this
    /// glyph from being a mouse-only door: the rest of the overlay is keyboard
    /// work, and this state happens once per install.
    private var settingsButton: some View {
        Button(action: onSettings) {
            Image(systemName: "info.circle")
                .foregroundStyle(hoveringSettings ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.plain)
        .onHover { hoveringSettings = $0 }
        .help(Text("Set your name in the sheet…"))
        .accessibilityLabel(Text("Set your name in the sheet…"))
    }

    /// `C2  14:00–14:45          in 20 min` — where, when, and how soon.
    ///
    /// The last column is the one a person actually reads: “14:00” on its own
    /// does not answer “is that now”. It also carries the day, which is why
    /// there is no separate date column. A booking on another day is dimmed a
    /// step, by colour rather than by weight.
    ///
    /// The columns are held by a minimum width on the first one rather than by
    /// a grid: space keys are two or three characters, so that is enough to
    /// line the times up, and it leaves the row a single view the selection can
    /// sit behind.
    ///
    /// Selected, the row takes a **neutral** fill and its text stops fading.
    /// Not the accent: the block is deliberately free of colour — “now” is
    /// marked by brightness for that reason — and a selection is a state of
    /// interaction rather than a piece of information. `.quaternary` is the
    /// system’s own token and follows both themes without a new colour.
    private func agendaRow(_ booking: Booking, selected: Bool) -> some View {
        let later = booking.date != today && !selected
        return HStack(spacing: 11) {
            Text(verbatim: booking.space.id)
                .fontWeight(.semibold)
                .frame(minWidth: 32, alignment: .leading)
                .foregroundStyle(later ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            Text(verbatim: "\(booking.start)–\(booking.end)")
                .monospacedDigit()
                .foregroundStyle(selected ? AnyShapeStyle(.primary)
                                          : (later ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary)))
            Spacer(minLength: 8)
            // Caption 1 from the HIG table, like every other aside in the
            // overlay: the column is a note next to the answer, not the answer.
            whenLabel(booking, selected: selected)
                .font(.caption)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6))
        // The fill bleeds six points either way so the text keeps the block’s
        // left edge; without this the rows would shift when selected.
        .padding(.horizontal, -6)
    }

    /// How soon it is.
    ///
    /// Within the hour the minutes are counted — that is the part worth acting
    /// on; further out the day is enough, because “in 3 h 25 min” has to be
    /// converted back in one’s head anyway.
    ///
    /// The imminent one is marked **by brightness, not by colour**: it simply
    /// does not fade the way the rest of the column does. A hue would have to
    /// be chosen for each theme separately — they are not mirror images — and
    /// red, tried first, read as an error. The same argument settled the window
    /// notches, which differ in thickness rather than in colour.
    @ViewBuilder
    private func whenLabel(_ booking: Booking, selected: Bool = false) -> some View {
        let quiet: AnyShapeStyle = selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
        if booking.date != today {
            Text(verbatim: "\(weekday(of: booking.date)) \(dayAndMonth(booking.date))")
                .foregroundStyle(quiet)
        } else if booking.start <= now {
            Text("now").foregroundStyle(.primary)
        } else if booking.start.minutes - now.minutes < 60 {
            Text("in \(String(booking.start.minutes - now.minutes)) min")
                .foregroundStyle(.primary)
        } else {
            Text("today").foregroundStyle(quiet)
        }
    }

    /// `21/09` — the year is noise next to a date days away, and it is the
    /// shape the query itself is written in.
    private func dayAndMonth(_ date: CalendarDate) -> String {
        String(format: "%02d/%02d", date.day, date.month)
    }

    /// The day for the dated example — the nearest one in the sheet after
    /// today, as `dd/mm`.
    ///
    /// A hard-coded date goes stale: typed verbatim a few days later, the
    /// example would become a request into the past, which the app answers
    /// with “that day is not in the sheet”. It is taken from the sheet rather
    /// than as `today + n`, because the sheet’s period slides.
    private func exampleDate(_ schedule: Schedule) -> String {
        dayAndMonth(schedule.dates.first { $0 > today } ?? schedule.dates.last ?? today)
    }

    @ViewBuilder
    private func result(_ query: Query, _ schedule: Schedule) -> some View {
        // The lists are always complete, even when a space is named: they
        // show where the arrows lead and what exists at this hour at all.
        // Complete within the chosen floor — the other one was switched off
        // by the person themselves.
        let visible = preferences.spaces(from: schedule.spaces)
        let free = Availability.fits(query.anySpace, in: schedule).filter(visible.contains)
        let busy = visible.filter {
            !Availability.occupants(of: $0, during: query, in: schedule).isEmpty
        }
        let requested = requestedSpace(query, schedule)
        let target = openCandidate(for: query, in: schedule, visibleFree: free)

        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "\(weekday(of: query.date)) \(query.date) · \(query.start)–\(query.end)")

            if schedule.dateIndex(of: query.date) == nil {
                missingDate(schedule)
            } else if free.isEmpty, busy.isEmpty {
                Text("That time is outside the grid — the day runs \(SheetGrid.dayStart.description) to \(SheetGrid.dayEnd.description)")
            } else {
                if let requested {
                    status(of: requested, query, schedule)
                }
                if !free.isEmpty {
                    spaceLine(Text("Free:"), free, selected: target?.id)
                }
                if !busy.isEmpty {
                    if free.isEmpty {
                        // Nothing is free — then the names matter: a bare
                        // “taken” does not say who to go and ask.
                        occupied(busy, query, schedule)
                    } else {
                        spaceLine(Text("Taken:"), busy, selected: requested?.id)
                    }
                }
                if let target {
                    HStack(spacing: 8) {
                        // Three forms, because ⏎ does three different things.
                        // With a name set it also copies it, and a hint that
                        // did not say so would leave the ⌘V undiscoverable;
                        // after a refusal it opens without the copy, and that
                        // has to be said before the press rather than after.
                        if clipboardRefused {
                            Text("Can’t put your clipboard back afterwards, so the name wasn’t copied — ⏎ again to open \(target.id) and pick the name there")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if preferences.bookingName != nil {
                            hint(Text("⏎ — open \(target.id) in the sheet, name copied"))
                        } else {
                            hint(Text("⏎ — open \(target.id) in the sheet"))
                        }
                        // The window describes what ⏎ will open, so it sits
                        // on the same line. When a space is named the window
                        // is already shown above, on its own line.
                        if requested == nil,
                           let window = Availability.freeWindow(for: query, in: target, of: schedule) {
                            windowChip(window, query)
                        }
                    }
                }
            }
            hint(Text("The grid is the next step"))
        }
    }

    /// The line about a named space: whether it is free, and how much room there is.
    @ViewBuilder
    private func status(of space: Space, _ query: Query, _ schedule: Schedule) -> some View {
        if let window = Availability.freeWindow(for: query, in: space, of: schedule) {
            HStack(spacing: 8) {
                Text("\(space.id) is free")
                windowChip(window, query)
            }
        } else {
            let occupants = Availability.occupants(of: space, during: query, in: schedule)
            if occupants.isEmpty {
                Text("\(space.id): that time is outside the grid")
            } else {
                Text("\(space.id) is taken: \(occupants.joined(separator: ", "))")
            }
        }
    }

    /// The bounds of the free run around the request, drawn as a chip so
    /// they can be seen rather than read out of a grey tail of text.
    ///
    /// The emphasis is shape rather than colour: a colour would have to be
    /// chosen for each theme separately — they are not mirror images — and on
    /// the dark one it glares.
    private func windowChip(_ window: Availability.FreeWindow, _ query: Query) -> some View {
        let times = "\(window.start.description)–\(window.end.description)"
        return HStack(spacing: 5) {
            edge(booking: window.startsAtBooking, flush: window.isTightBefore(query))
            Text(verbatim: times)
                .font(.caption)
                .foregroundStyle(.secondary)
            edge(booking: window.endsAtBooking, flush: window.isTightAfter(query))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(windowDescription(window, query))
    }

    /// An edge of the window: a solid wall is someone else’s booking, a hair
    /// line is merely the end of the day. A booking flush against the request
    /// is drawn heavier than a distant one — the difference is thickness
    /// rather than colour, because the two themes are not mirror images.
    private func edge(booking: Bool, flush: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(booking ? (flush ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                          : AnyShapeStyle(.quaternary))
            .frame(width: booking ? (flush ? 3 : 2) : 1, height: 12)
    }

    /// The same thing in words, for VoiceOver: the drawing tells it nothing.
    private func windowDescription(_ window: Availability.FreeWindow, _ query: Query) -> Text {
        let times = "\(window.start.description)–\(window.end.description)"
        switch (window.isTightBefore(query), window.isTightAfter(query)) {
        case (true, true): return Text("window \(times), back-to-back")
        case (true, false): return Text("window \(times), booking right before")
        case (false, true): return Text("window \(times), booking right after")
        case (false, false): return Text("window \(times)")
        }
    }

    /// “Free: C1, C2, …” with the space in question emphasised.
    private func spaceLine(_ label: Text, _ spaces: [Space], selected: String?) -> Text {
        spaces.reduce(label) { line, space in
            let separator = space.id == spaces.first?.id ? " " : ", "
            let item = Text(verbatim: space.id)
            return line + Text(verbatim: separator)
                + (space.id == selected ? item.bold().foregroundStyle(.primary) : item)
        }
    }

    /// Who holds what, by name. Shown only when nothing is free.
    private func occupied(_ spaces: [Space], _ query: Query, _ schedule: Schedule) -> Text {
        let parts = spaces.map { space in
            "\(space.id) — \(Availability.occupants(of: space, during: query, in: schedule).joined(separator: ", "))"
        }
        return Text("Taken:") + Text(verbatim: " " + parts.joined(separator: "; "))
    }

    /// The sheet’s period slides: past the tenth date there is simply nothing.
    @ViewBuilder
    private func missingDate(_ schedule: Schedule) -> some View {
        if let first = schedule.dates.first, let last = schedule.dates.last {
            Text("That day is not in the sheet — it holds \(String(schedule.dates.count)) dates, \(first.description)…\(last.description)")
        } else {
            Text("That day is not in the sheet")
        }
    }

    private func requestedSpace(_ query: Query, _ schedule: Schedule) -> Space? {
        query.spaceID.flatMap { id in schedule.spaces.first { $0.id == id } }
    }

    /// Spaces free for the request currently in the field. Empty means
    /// `QueryEdit` picks the ring itself and the arrow walks the whole
    /// catalogue.
    private func freeSpaces(in text: String) -> [Space] {
        guard let schedule = store.schedule,
              let query = QueryParser.parse(text, today: today, now: now)
        else { return preferences.spaces(from: Space.all) }
        let visible = preferences.spaces(from: schedule.spaces)
        return Availability.fits(query.anySpace, in: schedule).filter(visible.contains)
    }

    /// The weekday abbreviation comes from the system, along with the UI language.
    private func weekday(of date: CalendarDate) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols.indices.contains(date.weekdayIndex) ? symbols[date.weekdayIndex] : ""
    }

    /// Re-reading happens on every showing, so “show it again” is the retry.
    /// The combination is configurable and may be off altogether, so the hint
    /// is read from the setting rather than spelled out.
    private var retryHint: Text {
        guard let combo = preferences.hotKey else {
            return Text("Open it again from the menu bar to try again")
        }
        return Text("\(combo.description) twice to try again")
    }

    private func hint(_ text: Text) -> Text {
        text
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    /// ⇥ completes the request part by part, the way a shell completes a
    /// command: an empty field becomes the whole example, a named day gains an
    /// hour, a typed time a duration, then a space. When there is nothing left
    /// to add, it rewrites what was typed in canonical form, so that whatever
    /// the app filled in by itself becomes visible.
    ///
    /// The caret always lands at the end: completion is appended on the right.
    private func complete(_ current: String, _ caret: Int) -> QueryField.Edit {
        if current.trimmingCharacters(in: .whitespaces).isEmpty {
            return (placeholder, placeholder.utf16.count)
        }
        if let suggestion = QueryEdit.suggestion(after: current, today: today, now: now,
                                                 spaces: freeSpaces(in: current)) {
            let separator = current.hasSuffix(" ") ? "" : " "
            let completed = current + separator + suggestion
            return (completed, completed.utf16.count)
        }
        guard let parsed = QueryParser.parse(current, today: today, now: now) else { return nil }
        let completed = QueryParser.text(for: parsed, today: today)
        guard completed != current else { return nil }
        return (completed, completed.utf16.count)
    }

    private func open() {
        // A booking chosen with the arrows is what ⏎ acts on: with an empty
        // line there is no request to open, and until an arrow has been pressed
        // there is nothing chosen either — so ⏎ still does nothing by itself.
        if let booking = selectedBooking {
            act(on: booking.space, Query(
                date: booking.date,
                start: booking.start,
                minutes: booking.end.minutes - booking.start.minutes,
                spaceID: booking.space.id
            ))
            return
        }
        guard let query, let schedule = store.schedule else { return }
        let visible = preferences.spaces(from: schedule.spaces)
        let free = Availability.fits(query.anySpace, in: schedule).filter(visible.contains)
        guard let space = openCandidate(for: query, in: schedule, visibleFree: free) else { return }
        act(on: space, query)
    }

    /// The copy is skipped on the press that follows a refusal — the overlay
    /// has already said what will be lost, and this press is the answer.
    private func act(on space: Space, _ query: Query) {
        switch onOpen(space, query, !clipboardRefused) {
        case .clipboardUnavailable:
            clipboardRefused = true
        case .opened, .nothingToOpen:
            break
        }
    }

    private func openCandidate(for query: Query, in schedule: Schedule, visibleFree: [Space]) -> Space? {
        if let requested = requestedSpace(query, schedule) {
            return Availability.fits(query, in: schedule).first { $0.id == requested.id }
        }
        return visibleFree.first
    }
}

private struct OverlaySizeKey: PreferenceKey {
    static let defaultValue = CGSize(width: OverlayMetrics.width, height: 160)

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
