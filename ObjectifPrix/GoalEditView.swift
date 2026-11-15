import SwiftUI

// MARK: - Création / modification d'un objectif

struct GoalEditView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID?

    @State private var name = ""
    @State private var url = ""
    @State private var monthly = ""
    @State private var alert = ""
    @State private var currency = Prefs.defaultCurrency
    @State private var saveMode: SavingMode = .off
    @State private var saveAmount = ""
    @State private var saveDay = 1
    @State private var error = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    private var editing: Bool { goalID != nil }

    private var currencyChoices: [String] {
        Currencies.all.contains(currency) ? Currencies.all : [currency] + Currencies.all
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.t("edit.name_placeholder"), text: $name)
                } header: {
                    Text(L.t("edit.product"))
                }
                .listRowBackground(Theme.panel)

                Section {
                    TextField("https://…", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(L.t("edit.link"))
                } footer: {
                    Text(L.t("edit.link_help"))
                }
                .listRowBackground(Theme.panel)

                Section {
                    Picker(L.t("edit.currency"), selection: $currency) {
                        ForEach(currencyChoices, id: \.self) { code in
                            Text(code + " " + Currencies.symbolText(code)).tag(code)
                        }
                    }
                } footer: {
                    Text(L.t("edit.currency_help"))
                }
                .listRowBackground(Theme.panel)

                Section {
                    TextField(L.t("edit.monthly_placeholder"), text: $monthly)
                        .keyboardType(.decimalPad)
                } header: {
                    Text(L.t("edit.monthly"))
                } footer: {
                    Text(L.t("edit.monthly_help"))
                }
                .listRowBackground(Theme.panel)

                Section {
                    TextField(L.t("edit.alert_placeholder"), text: $alert)
                        .keyboardType(.decimalPad)
                } header: {
                    Text(L.t("edit.alert"))
                } footer: {
                    Text(L.t("edit.alert_help"))
                }
                .listRowBackground(Theme.panel)

                Section {
                    Picker(L.t("save.mode"), selection: $saveMode) {
                        ForEach(SavingMode.allCases) { mode in
                            Text(L.t(mode.labelKey)).tag(mode)
                        }
                    }
                    if saveMode != .off {
                        TextField(L.t("save.amount_ph"), text: $saveAmount)
                            .keyboardType(.decimalPad)
                    }
                    if saveMode == .monthly || saveMode == .auto {
                        Picker(L.t("save.day"), selection: $saveDay) {
                            ForEach(1...28, id: \.self) { day in
                                Text(String(day)).tag(day)
                            }
                        }
                    }
                } header: {
                    Text(L.t("save.section"))
                } footer: {
                    if saveMode == .auto {
                        Text(L.t("save.help_auto"))
                    } else if saveMode != .off {
                        Text(L.t("save.help_reminder"))
                    }
                }
                .listRowBackground(Theme.panel)

                if !error.isEmpty {
                    Section {
                        Text(error).foregroundStyle(Theme.bad)
                    }
                    .listRowBackground(Theme.panel)
                }

                if editing {
                    Section {
                        Button(L.t("edit.delete"), role: .destructive) {
                            if Prefs.confirmDelete {
                                confirmDelete = true
                            } else {
                                deleteNow()
                            }
                        }
                    }
                    .listRowBackground(Theme.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(editing ? L.t("edit.title_edit") : L.t("edit.title_new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.save"), action: save)
                        .fontWeight(.bold)
                }
            }
            .confirmationDialog(L.t("edit.delete_q"),
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L.t("common.delete"), role: .destructive) { deleteNow() }
                Button(L.t("common.cancel"), role: .cancel) {}
            }
            .onAppear(perform: loadIfNeeded)
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.scheme)
    }

    private func deleteNow() {
        if let id = goalID { store.delete(id) }
        dismiss()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let id = goalID, let g = store.goal(id) else { return }
        name = g.name
        url = g.url
        currency = g.cur
        monthly = g.monthly > 0 ? Fmt.plain(g.monthly) : ""
        alert = g.alertBelow > 0 ? Fmt.plain(g.alertBelow) : ""
        let rule: SavingRule = SavingRules.shared.rule(for: id)
        saveMode = rule.mode
        saveAmount = rule.amount > 0 ? Fmt.plain(rule.amount) : ""
        saveDay = min(max(rule.day, 1), 28)
    }

    private func save() {
        guard let m = Fmt.optionalAmount(monthly), let a = Fmt.optionalAmount(alert) else {
            error = L.t("edit.err_amounts")
            return
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURL.isEmpty {
            // accepte un lien collé avec du texte autour (bouton Partager) et retrouve l'adresse
            guard let parsed = PriceFetcher.cleanURL(cleanURL) else {
                error = L.t("edit.err_link")
                return
            }
            cleanURL = parsed.absoluteString
        }
        if cleanName.isEmpty && cleanURL.isEmpty {
            error = L.t("edit.err_empty")
            return
        }
        guard let rawSave = Fmt.optionalAmount(saveAmount) else {
            error = L.t("edit.err_amounts")
            return
        }
        if saveMode == .auto && rawSave <= 0 {
            error = L.t("err.save_amount")
            return
        }
        let rule = SavingRule(mode: saveMode, amount: rawSave, day: saveDay, lastAuto: "")

        if let id = goalID {
            let changed = store.edit(id, name: cleanName, url: cleanURL, monthly: m, alert: a, currency: currency)
            SavingRules.shared.set(rule, for: id)
            if changed && !cleanURL.isEmpty {
                Task { _ = await store.refresh(id, manual: true) }
            }
        } else {
            var goal = Goal(name: cleanName, url: cleanURL, monthly: m, alertBelow: a)
            goal.currency = currency
            store.add(goal)
            SavingRules.shared.set(rule, for: goal.id)
            if !cleanURL.isEmpty {
                let newID = goal.id
                Task { _ = await store.refresh(newID, manual: true) }
            }
        }
        if saveMode == .weekly || saveMode == .monthly { Notifier.requestPermission() }
        Reminders.reschedule(store: store)
        dismiss()
    }
}

// MARK: - Prix saisi à la main

struct ManualPriceView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID

    @State private var price = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.t("manual.placeholder"), text: $price)
                        .keyboardType(.decimalPad)
                } header: {
                    Text(L.f("manual.title_cur", store.goal(goalID)?.cur ?? Prefs.defaultCurrency))
                } footer: {
                    Text(footer)
                }
                .listRowBackground(Theme.panel)

                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(Theme.bad) }
                        .listRowBackground(Theme.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(L.t("menu.manual_price"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.save"), action: save)
                        .fontWeight(.bold)
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.scheme)
    }

    private var footer: String {
        var text = L.t("manual.help")
        if let g = store.goal(goalID), let p = g.price {
            text = L.f("manual.current", g.money(p)) + " " + text
        }
        return text
    }

    private func save() {
        guard let value = Fmt.amount(price), value > 0 else {
            error = L.t("manual.invalid")
            return
        }
        store.recordPrice(goalID, value, notify: false)
        dismiss()
    }
}
