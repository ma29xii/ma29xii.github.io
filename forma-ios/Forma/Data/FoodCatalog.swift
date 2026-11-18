import CoreFoundation
import Foundation

struct FoodSearchHit: Identifiable, Sendable {
    let id: String
    let name: String
    let brand: String?
}

enum FoodCatalogError: LocalizedError {
    case notFound, unavailable, busy, invalidResponse

    var errorDescription: String? {
        switch self {
        case .notFound: "Zu diesem Barcode gibt es keinen Treffer. Versuche es mit dem Produktnamen."
        case .unavailable: "Open Food Facts ist gerade nicht erreichbar. Versuch es später erneut."
        case .busy: "Die Suche ist gerade ausgelastet. Warte kurz und versuche es erneut."
        case .invalidResponse: "Die Produktdaten konnten nicht gelesen werden."
        }
    }
}

actor FoodCatalog {
    static let shared = FoodCatalog()

    private struct CachedProduct: Codable {
        let lookupCode: String
        let product: FoodProduct
    }

    private struct SearchRequest: Encodable {
        let q: String
        let langs = ["de", "en"]
        let fields = ["code", "product_name", "brands"]
        let page_size = 20
    }

    private let session: URLSession
    private let cacheURL: URL?
    private var cache: [CachedProduct]

    init(session: URLSession? = nil, cacheDirectory: URL? = URL.cachesDirectory) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: configuration)

        let url = cacheDirectory?.appending(path: "forma-food-products.json")
        cacheURL = url
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([CachedProduct].self, from: data) {
            cache = Array(saved.prefix(30))
        } else {
            cache = []
        }
    }

    func recentProducts() -> [FoodProduct] { cache.map(\.product) }

    func product(for code: String) async throws -> (product: FoodProduct, fromCache: Bool) {
        guard Self.isProductCode(code) else { throw FoodCatalogError.notFound }
        // https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/
        var components = URLComponents()
        components.scheme = "https"
        components.host = "world.openfoodfacts.org"
        components.path = "/api/v2/product/\(code).json"
        components.queryItems = [URLQueryItem(name: "fields", value:
            "code,product_name,product_name_de,brands,nutriments,serving_size,serving_quantity,serving_quantity_unit,product_quantity_unit"
        )]
        guard let url = components.url else { throw FoodCatalogError.invalidResponse }

        do {
            let data = try await fetch(URLRequest(url: url), isProductRequest: true)
            guard let product = try Self.decodeProduct(data) else { throw FoodCatalogError.notFound }
            remember(product, for: code)
            return (product, false)
        } catch FoodCatalogError.notFound {
            throw FoodCatalogError.notFound
        } catch {
            try Task.checkCancellation()
            let key = Self.cacheKey(for: code)
            if let saved = cache.first(where: {
                Self.cacheKey(for: $0.lookupCode) == key || Self.cacheKey(for: $0.product.code) == key
            }) {
                remember(saved.product, for: code)
                return (saved.product, true)
            }
            throw error
        }
    }

    func search(_ name: String) async throws -> [FoodSearchHit] {
        // https://openfoodfacts.github.io/search-a-licious/users/ref-openapi/
        let term = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard term.count >= 2 else { return [] }
        // Als Produktname suchen, ohne versehentlich Feldfilter aus der Lucene-Syntax zu übernehmen.
        let query = term.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
        var request = URLRequest(url: URL(string: "https://search.openfoodfacts.org/search")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SearchRequest(q: query))
        let data = try await fetch(request)
        return try Self.decodeSearch(data)
    }

    private func fetch(_ input: URLRequest, isProductRequest: Bool = false) async throws -> Data {
        var request = input
        request.setValue("Health-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            try Task.checkCancellation()
            throw FoodCatalogError.unavailable
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw FoodCatalogError.invalidResponse }
        switch response.statusCode {
        case 200...299: return data
        case 404 where isProductRequest: throw FoodCatalogError.notFound
        case 429: throw FoodCatalogError.busy
        default: throw FoodCatalogError.unavailable
        }
    }

    private func remember(_ product: FoodProduct, for code: String) {
        let key = Self.cacheKey(for: product.code)
        cache.removeAll { $0.lookupCode == code || Self.cacheKey(for: $0.product.code) == key }
        cache.insert(CachedProduct(lookupCode: code, product: product), at: 0)
        if cache.count > 30 { cache.removeLast() }
        if let cacheURL, let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private static func cacheKey(for code: String) -> String {
        code.count == 13 && code.hasPrefix("0") ? String(code.dropFirst()) : code
    }

    static func decodeProduct(_ data: Data) throws -> FoodProduct? {
        let envelope = try jsonObject(data)
        if number(envelope["status"]) == 0 { return nil }
        guard number(envelope["status"]) == 1,
              let fields = envelope["product"] as? [String: Any],
              let hit = hit(from: fields, fallbackCode: envelope["code"]) else {
            throw FoodCatalogError.invalidResponse
        }

        let serving = servingAmount(fields)
        let base = foodBase(fields["product_quantity_unit"]) ?? serving?.unit
            ?? foodBase(fields["serving_quantity_unit"]) ?? .grams
        let size = serving.flatMap { $0.unit == base ? $0.amount : nil }
        let nutriments = fields["nutriments"] as? [String: Any] ?? [:]
        let declared100 = nutrients(nutriments, suffix: "_100g", base: base, referenceSize: 100)
        let declaredServing = nutrients(nutriments, suffix: "_serving", base: base, referenceSize: size)
        let inferred100 = size.map { declaredServing.scaled(by: 100 / $0) } ?? FoodNutrients()
        let inferredServing = size.map { declared100.scaled(by: $0 / 100) } ?? FoodNutrients()
        return FoodProduct(code: hit.id, name: hit.name, brand: hit.brand, base: base, servingSize: size,
                           per100: declared100.fillingMissing(from: inferred100),
                           perServing: declaredServing.fillingMissing(from: inferredServing))
    }

    static func decodeSearch(_ data: Data) throws -> [FoodSearchHit] {
        guard let hits = try jsonObject(data)["hits"] as? [Any] else {
            throw FoodCatalogError.invalidResponse
        }
        var seen = Set<String>()
        return hits.compactMap { raw in
            guard let fields = raw as? [String: Any],
                  let product = hit(from: fields), seen.insert(product.id).inserted else { return nil }
            return product
        }
    }

    static func barcode(_ payload: String, isUPCE: Bool) -> String? {
        guard isProductCode(payload), [8, 12, 13].contains(payload.count) else { return nil }
        guard isUPCE else { return payload }
        let digits = Array(payload)
        guard digits.count == 8, digits[0] == "0" || digits[0] == "1" else { return nil }
        // UPC-E komprimiert die Nullen aus UPC-A. Acht Stellen allein unterscheiden UPC-E und EAN-8 nicht.
        let expanded: String
        switch digits[6] {
        case "0", "1", "2":
            expanded = "\(String(digits[0...2]))\(digits[6])0000\(String(digits[3...5]))"
        case "3":
            expanded = "\(String(digits[0...3]))00000\(String(digits[4...5]))"
        case "4":
            expanded = "\(String(digits[0...4]))00000\(digits[5])"
        default:
            expanded = "\(String(digits[0...5]))0000\(digits[6])"
        }
        return expanded + String(digits[7])
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FoodCatalogError.invalidResponse
        }
        return object
    }

    private static func isProductCode(_ value: String) -> Bool {
        (4...24).contains(value.utf8.count) && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func hit(from fields: [String: Any], fallbackCode: Any? = nil) -> FoodSearchHit? {
        guard let code = text(fields["code"]) ?? text(fallbackCode), isProductCode(code) else { return nil }
        let names = (fields["brands"] as? [String]) ?? [text(fields["brands"])].compactMap { $0 }
        var unique = Set<String>()
        let brands = names.compactMap { text($0) }.filter { unique.insert($0.lowercased()).inserted }
        let name = text(fields["product_name_de"]) ?? text(fields["product_name"]) ?? "Produkt \(code)"
        return FoodSearchHit(id: code, name: name, brand: text(brands.joined(separator: ", ")))
    }

    private static func text(_ raw: Any?) -> String? {
        guard let value = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return String(value.prefix(160))
    }

    private static func number(_ raw: Any?) -> Double? {
        let result: Double?
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            result = number.doubleValue
        } else {
            result = text(raw).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        }
        return result.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    private static func foodBase(_ raw: Any?) -> FoodBase? {
        guard let unit = text(raw)?.lowercased() else { return nil }
        switch unit {
        case "g", "kg", "mg": return .grams
        case "ml", "cl", "dl", "l": return .milliliters
        default: return nil
        }
    }

    private static func servingAmount(_ fields: [String: Any]) -> (unit: FoodBase, amount: Double)? {
        if let amount = number(fields["serving_quantity"]),
           let measure = normalizedAmount(amount, unit: fields["serving_quantity_unit"]) {
            return measure
        }
        guard let label = text(fields["serving_size"]),
              let match = label.range(of: #"\d+(?:[.,]\d+)?\s*(?:kg|mg|ml|cl|dl|g|l)\b"#,
                                      options: [.regularExpression, .caseInsensitive]) else { return nil }
        let measure = label[match]
        guard let unitStart = measure.firstIndex(where: \.isLetter),
              let amount = number(String(measure[..<unitStart])) else { return nil }
        return normalizedAmount(amount, unit: String(measure[unitStart...]))
    }

    private static func normalizedAmount(_ amount: Double, unit raw: Any?) -> (FoodBase, Double)? {
        guard let unit = text(raw)?.lowercased(), let base = foodBase(unit) else { return nil }
        let factor: Double
        switch unit {
        case "mg": factor = 0.001
        case "cl": factor = 10
        case "dl": factor = 100
        case "kg", "l": factor = 1_000
        default: factor = 1
        }
        let amount = amount * factor
        return (0.01...10_000).contains(amount) ? (base, amount) : nil
    }

    private static func nutrients(_ fields: [String: Any], suffix: String, base: FoodBase,
                                  referenceSize: Double?) -> FoodNutrients {
        let pairs = FoodNutrient.allCases.compactMap { nutrient -> (FoodNutrient, Double)? in
            var value = number(fields[nutrient.rawValue + suffix])
            if nutrient == .energy, value == nil {
                // OFF speichert "energy" als kJ. Das Feld "energy-kcal" hat Vorrang.
                value = (number(fields["energy-kj" + suffix]) ?? number(fields["energy" + suffix])).map { $0 / 4.184 }
            }
            // Flüssigkeiten können je 100 ml mehr als 100 g wiegen. Kleine Rundungsdifferenzen zulassen.
            let maxMass = base == .grams ? 1.01 : 2.0
            let limit = referenceSize.map { $0 * maxMass * (nutrient == .energy ? 10 : 1) } ?? 100_000
            guard let value, value <= limit else { return nil }
            return (nutrient, value)
        }
        return FoodNutrients(values: Dictionary(uniqueKeysWithValues: pairs))
    }
}
