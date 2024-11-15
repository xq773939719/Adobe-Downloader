import Foundation

class NetworkService {
    typealias ProductsData = (products: [String: Sap], cdn: String, sapCodes: [SapCodes])

    private func makeProductsURL() throws -> URL {
        var components = URLComponents(string: NetworkConstants.productsXmlURL)
        components?.queryItems = [
            URLQueryItem(name: "_type", value: "xml"),
            URLQueryItem(name: "channel", value: "ccm"),
            URLQueryItem(name: "channel", value: "sti"),
            URLQueryItem(name: "platform", value: "osx10-64,osx10,macarm64,macuniversal"),
            URLQueryItem(name: "productType", value: "Desktop")
        ]

        guard let url = components?.url else {
            throw NetworkError.invalidURL(NetworkConstants.productsXmlURL)
        }
        print(url)
        return url
    }

    private func configureRequest(_ request: inout URLRequest, headers: [String: String]) {
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    }

    func fetchProductsData(platform: String) async throws -> ProductsData {
        let url = try makeProductsURL()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        configureRequest(&request, headers: NetworkConstants.adobeRequestHeaders)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode, nil)
        }

        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw NetworkError.invalidData("无法解码XML数据")
        }

        let result: ProductsData = try await Task.detached(priority: .userInitiated) {
            let parseResult = try XHXMLParser.parse(xmlString: xmlString)
            let products = parseResult.products, cdn = parseResult.cdn
            var sapCodes: [SapCodes] = []
            let allowedPlatforms = ["macuniversal", "macarm64", "osx10-64", "osx10"]
            for product in products.values {
                if product.isValid {
                    var lastVersion: String? = nil
                    for version in product.versions.values.reversed() {
                        if !version.buildGuid.isEmpty && allowedPlatforms.contains(version.apPlatform) {
                            lastVersion = version.productVersion
                            break
                        }
                    }
                    if lastVersion != nil {
                        sapCodes.append(SapCodes(
                            sapCode: product.sapCode,
                            displayName: product.displayName
                        ))
                    }
                }
            }
            return (products, cdn, sapCodes)
        }.value

        return result
    }

    func getApplicationInfo(buildGuid: String) async throws -> String {
        guard let url = URL(string: NetworkConstants.applicationJsonURL) else {
            throw NetworkError.invalidURL(NetworkConstants.applicationJsonURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        var headers = NetworkConstants.adobeRequestHeaders
        headers["x-adobe-build-guid"] = buildGuid
        headers["Cookie"] = generateCookie()

        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NetworkError.invalidData("无法将响应数据转换为json符串")
        }

        return jsonString
    }

    private func generateCookie() -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = Int.random(in: 100000...999999)
        return "s_cc=true; s_sq=; AMCV_9E1005A551ED61CA0A490D45%40AdobeOrg=1075005958%7CMCIDTS%7C\(timestamp)%7CMCMID%7C\(random)%7CMCAAMLH-1683925272%7C11%7CMCAAMB-1683925272%7CRKhpRz8krg2tLO6pguXWp5olkAcUniQYPHaMWWgdJ3xzPWQmdj0y%7CMCOPTOUT-1683327672s%7CNONE%7CvVersion%7C4.4.1; gpv=cc-search-desktop; s_ppn=cc-search-desktop"
    }
}
