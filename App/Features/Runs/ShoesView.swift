import SwiftUI
import Insights
import Store
import RunKit

/// Zapatillas: kilómetros de cada par y aviso cuando llegan a su límite (doc. 18 §6).
struct ShoesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Shoe?
    @State private var adding = false

    var body: some View {
        let runs = model.runs
        let km = runs.history.shoeKilometers(shoes: runs.shoes, assignments: runs.assignments)
        let active = runs.shoes.filter { !$0.retired }
        let retired = runs.shoes.filter(\.retired)
        List {
            Section {
                if active.isEmpty {
                    Text("Aún no has añadido zapatillas.").foregroundStyle(Palette.textSecondary)
                }
                ForEach(active) { shoe in row(shoe, km: km[shoe.id] ?? shoe.startKm) }
            } header: {
                Text("En uso")
            } footer: {
                Text("Las predeterminadas se asignan solas a tus carreras desde el día en que las añades; en cada carrera puedes elegir otras.")
            }
            if !retired.isEmpty {
                Section("Retiradas") {
                    ForEach(retired) { shoe in row(shoe, km: km[shoe.id] ?? shoe.startKm) }
                }
            }
        }
        .navigationTitle("Zapatillas")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Añadir zapatillas")
            }
        }
        .sheet(isPresented: $adding) { ShoeEditor(shoe: nil) }
        .sheet(item: $editing) { shoe in ShoeEditor(shoe: shoe) }
    }

    private func row(_ shoe: Shoe, km: Double) -> some View {
        Button { editing = shoe } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(shoe.name).font(.body.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                    if shoe.isDefault { Text("Predeterminadas").font(.caption).foregroundStyle(Palette.textSecondary) }
                    Spacer()
                    Text("\(Int(km.rounded())) km").monospacedDigit().foregroundStyle(Palette.textPrimary)
                }
                ProgressView(value: min(km, shoe.limitKm), total: max(1, shoe.limitKm))
                    .tint(km >= shoe.limitKm ? Palette.recoveryLow : (km >= 0.8 * shoe.limitKm ? Palette.recoveryMedium : Palette.recoveryHigh))
                Text(km >= shoe.limitKm ? "Han pasado de los \(Int(shoe.limitKm)) km: plantéate cambiarlas."
                                        : "Les quedan unos \(Int((shoe.limitKm - km).rounded())) km.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

struct ShoeEditor: View {
    let shoe: Shoe?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var startKm = 0.0
    @State private var limitKm = 700.0
    @State private var isDefault = false
    @State private var retired = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre (p. ej. Pegasus 41)", text: $name)
                    Stepper("Km que ya tenían: \(Int(startKm))", value: $startKm, in: 0...3000, step: 10)
                    Stepper("Cambiarlas a los \(Int(limitKm)) km", value: $limitKm, in: 200...1500, step: 50)
                    Toggle("Predeterminadas", isOn: $isDefault)
                } footer: {
                    Text("Unas zapatillas de entrenamiento suelen durar 500–800 km; las de competición, 300–500.")
                }
                if shoe != nil {
                    Section {
                        Toggle("Retiradas", isOn: $retired)
                        Button("Borrar", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(shoe == nil ? "Nuevas zapatillas" : "Editar zapatillas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("¿Borrar estas zapatillas?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) { delete() }
            } message: {
                Text("Las carreras que tenían asignadas quedan sin zapatillas.")
            }
            .onAppear {
                guard let shoe else { return }
                name = shoe.name
                startKm = shoe.startKm
                limitKm = shoe.limitKm
                isDefault = shoe.isDefault
                retired = shoe.retired
            }
        }
    }

    private func save() {
        var list = model.runs.shoes
        var s = shoe ?? Shoe(name: name)
        s.name = name.trimmingCharacters(in: .whitespaces)
        s.startKm = startKm
        s.limitKm = limitKm
        s.isDefault = isDefault && !retired
        s.retired = retired
        if s.isDefault { for i in list.indices { list[i].isDefault = false } }
        if let i = list.firstIndex(where: { $0.id == s.id }) { list[i] = s } else { list.append(s) }
        model.runs.saveShoes(list, model: model)
        dismiss()
    }

    private func delete() {
        guard let shoe else { return }
        model.runs.saveShoes(model.runs.shoes.filter { $0.id != shoe.id }, model: model)
        dismiss()
    }
}
