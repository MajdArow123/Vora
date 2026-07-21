//
//  OpenFoodFactsClient.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

enum OpenFoodFactsError: LocalizedError {
    case invalidURL
    case badResponse
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid request."
        case .badResponse: "OpenFoodFacts is unreachable right now."
        case .productNotFound: "No product found for that barcode."
        }
    }
}

struct OpenFoodFactsClient {
    private static let userAgent = "Vora/1.0 (iOS; https://github.com/MajdArow123)"
    private static let nutrimentFields = "code,product_name,brands,serving_quantity,nutriments"

    func search(_ query: String) async throws -> [FoodItem] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "fields", value: Self.nutrimentFields),
        ]
        guard let url = components?.url else { throw OpenFoodFactsError.invalidURL }

        let response: OFFSearchResponse = try await fetch(url)
        return response.products.compactMap(FoodItem.init(offProduct:))
    }

    func product(barcode: String) async throws -> FoodItem {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=\(Self.nutrimentFields)")
        else { throw OpenFoodFactsError.invalidURL }

        let response: OFFProductResponse = try await fetch(url)
        guard response.status == 1,
              let product = response.product,
              let item = FoodItem(offProduct: product)
        else { throw OpenFoodFactsError.productNotFound }
        return item
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenFoodFactsError.badResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
