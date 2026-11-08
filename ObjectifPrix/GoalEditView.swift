import SwiftUI

// MARK: - Création / modification d'un objectif

struct GoalEditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID?

    @State private var name = ""
    @State private var url = ""
    @State private var monthly = ""
    @State private var alert = ""
    @State private var error = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    private var editing: Bool { goalID != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ex : Apple Watch SE 3", text: $name)
                } header: {
                    Text("Produit")
                }
                .listRowBackground(Theme.panel)

                Section {
                    TextField("https://www.idealo.fr/…", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Lien idealo")
                } footer: {
                    Text("Adresse de la page produit. Vide = tu saisis le prix à la main.")
                }
                .listRowBackground(Theme.panel)

                Section {
                    TextField("Ex : 50", text: $monthly)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Épargne par mois (€)")
                } footer: {
                    Text("Sert à estimer la date à laquelle tu pourras l'acheter.")
                }
                .listRowBackground(Theme.panel)

                Section {
                    TextField("Ex : 250", text: $alert)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Alerte si le prix passe sous (€)")
                } footer: {
                    Text("Tu reçois une notification quand le prix descend sous ce seuil.")
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
                        Button("Supprimer cet objectif", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                    .listRowBackground(Theme.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(editing ? "Modifier l'objectif" : "Nouvel objectif")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .fontWeight(.bold)
                }
            }
            .confirmationDialog("Supprimer cet objectif et son historique ?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let id = goalID { store.delete(id) }
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            }
            .onAppear(perform: loadIfNeeded)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let id = goalID, let g = store.goal(id) else { return }
        name = g.name
        url = g.url
        monthly = g.monthly > 0 ? Fmt.plain(g.monthly) : ""
        alert = g.alertBelow > 0 ? Fmt.plain(g.alertBelow) : ""
    }

    private func save() {
        guard let m = Fmt.optionalAmount(monthly), let a = Fmt.optionalAmount(alert) else {
            error = "Les montants doivent être des nombres positifs (ex : 50 ou 12,5)."
            return
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleanURL.lowercased()
        if !cleanURL.isEmpty && !(lower.hasPrefix("http://") || lower.hasPrefix("https://")) {
            error = "Le lien doit commencer par http:// ou https://"
            return
        }
        if cleanName.isEmpty && cleanURL.isEmpty {
            error = "Donne au moins un nom ou un lien."
            return
        }

        if let id = goalID {
            let changed = store.edit(id, name: cleanName, url: cleanURL, monthly: m, alert: a)
            if changed && !cleanURL.isEmpty {
                Task { _ = await store.refresh(id, manual: true) }
            }
        } else {
            let goal = Goal(name: cleanName, url: cleanURL, monthly: m, alertBelow: a)
            store.add(goal)
            if !cleanURL.isEmpty {
                Task { _ = await store.refresh(goal.id, manual: true) }
            }
        }
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
                    TextField("Ex : 279,99", text: $price)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Prix (€)")
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
            .navigationTitle("Prix manuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .fontWeight(.bold)
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var footer: String {
        var text = "Pratique si le site bloque la lecture automatique. Le prochain relevé automatique pourra le remplacer."
        if let p = store.goal(goalID)?.price {
            text = "Prix actuel enregistré : \(Fmt.euro(p)). " + text
        }
        return text
    }

    private func save() {
        guard let value = Fmt.amount(price), value > 0 else {
            error = "Entre un prix valide (ex : 279 ou 279,99)."
            return
        }
        store.recordPrice(goalID, value, notify: false)
        dismiss()
    }
}
