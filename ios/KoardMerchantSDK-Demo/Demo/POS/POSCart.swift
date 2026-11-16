import Foundation

/// A local sample menu and ticket. Checkout still uses the selected merchant's
/// payment settings; these items do not create a server-side inventory or order.
enum POSCategory: String, CaseIterable, Identifiable {
    case favorites = "Favorites"
    case coffee = "Coffee"
    case kitchen = "Kitchen"
    case drinks = "Drinks"
    case goods = "Goods"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .favorites: return "star.fill"
        case .coffee: return "cup.and.saucer.fill"
        case .kitchen: return "fork.knife"
        case .drinks: return "wineglass.fill"
        case .goods: return "bag.fill"
        }
    }
}

struct POSMenuItem: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let priceCents: Int
    let category: POSCategory
    let isFavorite: Bool

    static let sampleMenu: [POSMenuItem] = [
        .init(id: "latte", name: "Latte", detail: "Double shot · 12 oz", priceCents: 550, category: .coffee, isFavorite: true),
        .init(id: "cold-brew", name: "Cold brew", detail: "Slow steeped · 16 oz", priceCents: 600, category: .coffee, isFavorite: true),
        .init(id: "espresso", name: "Espresso", detail: "Double shot", priceCents: 350, category: .coffee, isFavorite: false),
        .init(id: "cappuccino", name: "Cappuccino", detail: "Double shot · 8 oz", priceCents: 500, category: .coffee, isFavorite: false),
        .init(id: "avocado-toast", name: "Avocado toast", detail: "Sourdough · chili · lime", priceCents: 1200, category: .kitchen, isFavorite: true),
        .init(id: "breakfast-sandwich", name: "Breakfast sandwich", detail: "Egg · cheddar · brioche", priceCents: 1050, category: .kitchen, isFavorite: true),
        .init(id: "croissant", name: "Butter croissant", detail: "Baked this morning", priceCents: 450, category: .kitchen, isFavorite: true),
        .init(id: "burger", name: "House burger", detail: "Cheddar · pickles · fries", priceCents: 1800, category: .kitchen, isFavorite: false),
        .init(id: "paloma", name: "Paloma", detail: "Tequila · grapefruit · lime", priceCents: 1400, category: .drinks, isFavorite: true),
        .init(id: "draft", name: "Draft lager", detail: "Local draft · 16 oz", priceCents: 750, category: .drinks, isFavorite: false),
        .init(id: "sparkling", name: "Sparkling water", detail: "Chilled · 12 oz", priceCents: 350, category: .drinks, isFavorite: false),
        .init(id: "beans", name: "House coffee beans", detail: "Whole bean · 12 oz", priceCents: 1900, category: .goods, isFavorite: true),
        .init(id: "tumbler", name: "Travel tumbler", detail: "Insulated · 16 oz", priceCents: 2400, category: .goods, isFavorite: false),
    ]
}

struct POSTicketLine: Identifiable, Equatable {
    let id: String
    let name: String
    let unitPriceCents: Int
    var quantity: Int
    var totalCents: Int { unitPriceCents * quantity }
}

struct POSCart: Equatable {
    let maximumCents: Int
    private(set) var lines: [POSTicketLine] = []
    var subtotalCents: Int { lines.reduce(0) { $0 + $1.totalCents } }
    var itemCount: Int { lines.reduce(0) { $0 + $1.quantity } }

    init(maximumCents: Int = 99_999_999) {
        self.maximumCents = max(1, maximumCents)
    }

    @discardableResult
    mutating func add(_ item: POSMenuItem) -> Bool {
        guard item.priceCents > 0, item.priceCents <= maximumCents - subtotalCents else { return false }
        if let index = lines.firstIndex(where: { $0.id == item.id }) {
            lines[index].quantity += 1
        } else {
            lines.append(.init(id: item.id, name: item.name, unitPriceCents: item.priceCents, quantity: 1))
        }
        return true
    }

    @discardableResult
    mutating func addCustomAmount(_ cents: Int) -> Bool {
        guard cents > 0, cents <= maximumCents - subtotalCents else { return false }
        lines.append(.init(id: UUID().uuidString, name: "Custom amount", unitPriceCents: cents, quantity: 1))
        return true
    }

    mutating func changeQuantity(lineID: String, by delta: Int) {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        if delta == 1 {
            guard lines[index].unitPriceCents <= maximumCents - subtotalCents else { return }
            lines[index].quantity += 1
        } else if delta == -1 {
            if lines[index].quantity == 1 { lines.remove(at: index) }
            else { lines[index].quantity -= 1 }
        }
    }

    mutating func clear() { lines.removeAll() }
}
