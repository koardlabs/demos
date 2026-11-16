import SwiftUI

/// Item entry and ticket editing only. The parent owns the existing SDK checkout.
struct POSRegisterWorkspace: View {
    let subtotalCents: Int
    let onSubtotalChange: (Int) -> Void
    let onCheckout: () -> Void
    let isProcessing: Bool
    let taxCents: Int

    @State private var cart = POSCart(maximumCents: PinPadAmount.maxCents)
    @State private var category: POSCategory = .favorites
    @State private var search = ""
    @State private var showsCustomAmount = false
    @State private var showsTicket = false
    @State private var checkoutAfterTicketDismissal = false
    @State private var entryError: String?

    private var filteredItems: [POSMenuItem] {
        POSMenuItem.sampleMenu.filter {
            (category == .favorites ? $0.isFavorite : $0.category == category)
                && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 760 {
                HStack(spacing: 0) {
                    menu.padding(24)
                    ticket
                        .frame(width: min(380, geometry.size.width * 0.38))
                        .background(POSDesign.surface)
                        .overlay(alignment: .leading) { Rectangle().fill(POSDesign.line).frame(width: 1) }
                }
            } else {
                menu
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .safeAreaInset(edge: .bottom, spacing: 0) { compactTicketBar }
            }
        }
        .background(POSDesign.background)
        .disabled(isProcessing)
        .onChange(of: subtotalCents) { _, updated in
            // The checkout driver clears its amount after a completed charge.
            if updated == 0 { cart.clear() }
        }
        .sheet(isPresented: $showsCustomAmount) {
            POSCustomAmountSheet { cents in
                if cart.addCustomAmount(cents) { publishTicket() }
                else { entryError = "This ticket has reached the maximum amount." }
            }
        }
        .sheet(isPresented: $showsTicket, onDismiss: {
            if checkoutAfterTicketDismissal {
                checkoutAfterTicketDismissal = false
                onCheckout()
            }
        }) {
            NavigationStack {
                ticket
                    .navigationTitle("Current ticket")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showsTicket = false } } }
            }
            .presentationDetents([.large])
        }
        .alert("Amount unavailable", isPresented: Binding(get: { entryError != nil }, set: { if !$0 { entryError = nil } })) {
            Button("OK") { entryError = nil }
        } message: { Text(entryError ?? "") }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New ticket").font(.system(size: 28, weight: .bold)).foregroundStyle(POSDesign.ink)
                    Text("Sample menu").font(.caption).foregroundStyle(POSDesign.muted)
                }
                Spacer()
                Button { showsCustomAmount = true } label: { Label("Amount", systemImage: "plus") }
                    .buttonStyle(POSButtonStyle())
                    .accessibilityIdentifier("pos.customAmount")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(POSDesign.muted)
                TextField("Find an item", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pos.search")
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") } }
            }
            .padding(12)
            .background(POSDesign.surface, in: RoundedRectangle(cornerRadius: 10))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(POSCategory.allCases) { option in
                        Button { category = option } label: {
                            Label(option.rawValue, systemImage: option.symbol)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .foregroundStyle(category == option ? .white : POSDesign.ink)
                                .background(category == option ? Color.koardGreen : POSDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pos.category.\(option.id)")
                        .accessibilityAddTraits(category == option ? .isSelected : [])
                    }
                }
            }

            ScrollView {
                if filteredItems.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(filteredItems) { item in
                            menuTile(item)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func menuTile(_ item: POSMenuItem) -> some View {
        Button {
            if cart.add(item) {
                publishTicket()
                HapticFeedback.lightImpact.impactOccurred()
            } else { entryError = "This ticket has reached the maximum amount." }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: item.category.symbol)
                        .foregroundStyle(POSDesign.accent(for: item.category))
                    Spacer()
                    if let line = cart.lines.first(where: { $0.id == item.id }) {
                        Text("\(line.quantity)")
                            .font(.caption.weight(.bold))
                            .padding(6)
                            .background(Color.koardGreen.opacity(0.12), in: Circle())
                    } else { Image(systemName: "plus").font(.caption).foregroundStyle(POSDesign.muted) }
                }
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(POSDesign.muted)
                    .lineLimit(2)
                    .frame(minHeight: 28, alignment: .top)
                Divider()
                Text(MoneyUtils.centsToStringWithCurrency(item.priceCents))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(POSDesign.ink)
            .padding(16)
            .background(POSDesign.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                    .fill(POSDesign.accent(for: item.category)).frame(width: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(item.name), \(MoneyUtils.centsToStringWithCurrency(item.priceCents))")
        .accessibilityIdentifier("pos.item.\(item.id)")
    }

    private var ticket: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current ticket").font(.title3.weight(.bold))
                    Text("\(cart.itemCount) items").font(.caption).foregroundStyle(POSDesign.muted)
                }
                Spacer()
                Button("Clear") { cart.clear(); publishTicket() }
                    .foregroundStyle(POSDesign.muted)
                    .disabled(cart.lines.isEmpty)
                    .accessibilityIdentifier("pos.clear")
            }
            .padding(20)
            Divider()
            ScrollView {
                if cart.lines.isEmpty {
                    ContentUnavailableView("Start a ticket", systemImage: "receipt", description: Text("Add menu items or enter a custom amount."))
                        .padding(.top, 32)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(cart.lines) { line in ticketLine(line); Divider().padding(.horizontal, 20) }
                    }
                }
            }
            totals.padding(20)
            Button {
                if showsTicket {
                    checkoutAfterTicketDismissal = true
                    showsTicket = false
                } else { onCheckout() }
            } label: {
                HStack { Text("Review payment"); Spacer(); Image(systemName: "arrow.right") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(POSButtonStyle(prominent: true))
            .disabled(subtotalCents == 0)
            .accessibilityIdentifier("pos.checkout")
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .foregroundStyle(POSDesign.ink)
        .background(POSDesign.surface)
    }

    private func ticketLine(_ line: POSTicketLine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(line.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(MoneyUtils.centsToStringWithCurrency(line.totalCents)).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            HStack(spacing: 0) {
                quantityButton(line, delta: -1, symbol: "minus")
                Text("\(line.quantity)").font(.subheadline.weight(.semibold)).frame(width: 34)
                quantityButton(line, delta: 1, symbol: "plus")
                Spacer()
                Text("\(MoneyUtils.centsToStringWithCurrency(line.unitPriceCents)) each").font(.caption).foregroundStyle(POSDesign.muted)
            }
        }
        .padding(20)
    }

    private func quantityButton(_ line: POSTicketLine, delta: Int, symbol: String) -> some View {
        Button {
            cart.changeQuantity(lineID: line.id, by: delta)
            publishTicket()
        } label: {
            Image(systemName: symbol).font(.caption.weight(.bold)).frame(width: 44, height: 44)
                .background(POSDesign.background, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(delta > 0 ? "Increase" : "Decrease") \(line.name)")
        .accessibilityIdentifier("pos.quantity.\(line.id).\(delta > 0 ? "plus" : "minus")")
    }

    private var totals: some View {
        VStack(spacing: 10) {
            totalRow("Subtotal", subtotalCents)
            if taxCents > 0 { totalRow("Tax", taxCents) }
            Divider()
            HStack {
                Text("Before tip").font(.subheadline.weight(.semibold))
                Spacer()
                Text(MoneyUtils.centsToStringWithCurrency(subtotalCents + taxCents))
                    .font(.title2.weight(.bold)).monospacedDigit()
                    .accessibilityIdentifier("pos.total")
            }
            Text("Tip and any surcharge are confirmed at payment.")
                .font(.caption).foregroundStyle(POSDesign.muted).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func totalRow(_ label: String, _ cents: Int) -> some View {
        HStack { Text(label); Spacer(); Text(MoneyUtils.centsToStringWithCurrency(cents)).monospacedDigit() }
            .font(.subheadline).foregroundStyle(POSDesign.muted)
    }

    private var compactTicketBar: some View {
        HStack(spacing: 12) {
            Button { showsTicket = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) { Text("Ticket · \(cart.itemCount)"); Image(systemName: "chevron.up") }
                        .font(.caption.weight(.semibold))
                    Text(MoneyUtils.centsToStringWithCurrency(subtotalCents)).font(.title3.weight(.bold)).monospacedDigit()
                }
                .frame(minWidth: 94, minHeight: 48, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(POSDesign.ink)
            .accessibilityIdentifier("pos.ticket")
            Button(action: onCheckout) {
                HStack { Text("Review payment"); Spacer(); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity)
            }
            .buttonStyle(POSButtonStyle(prominent: true))
            .disabled(subtotalCents == 0)
            .accessibilityIdentifier("pos.checkout")
        }
        .padding(16)
        .background(POSDesign.surface)
        .overlay(alignment: .top) { Divider() }
    }

    private func publishTicket() { onSubtotalChange(cart.subtotalCents) }
}

private struct POSCustomAmountSheet: View {
    let onAdd: (Int) -> Void
    @State private var amount = PinPadAmount()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text(amount.formattedDisplay).font(.system(size: 48, weight: .bold)).monospacedDigit()
                        .minimumScaleFactor(0.4).lineLimit(1).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("pos.customTotal")
                    Text("Enter an amount to add to this ticket.").font(.subheadline).foregroundStyle(POSDesign.muted)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(1...9, id: \.self) { digit in PinPadKeyButton(key: .digit(digit)) { amount.append(digit: digit) } }
                        PinPadKeyButton(key: .doubleZero) { amount.append(digit: 0); amount.append(digit: 0) }
                        PinPadKeyButton(key: .digit(0)) { amount.append(digit: 0) }
                        PinPadKeyButton(key: .backspace) { amount.backspace() }
                    }
                }
                .padding(24)
            }
            .background(POSDesign.background)
            .navigationTitle("Custom amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button { onAdd(amount.cents); dismiss() } label: {
                    Text("Add to ticket").frame(maxWidth: .infinity)
                }
                .buttonStyle(POSButtonStyle(prominent: true))
                .disabled(amount.isZero)
                .accessibilityIdentifier("pos.customAdd")
                .padding(20).background(POSDesign.surface)
            }
        }
    }
}
