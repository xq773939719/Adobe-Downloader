//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation

struct Product: Identifiable {
    let id: String
    var hidden: Bool
    var displayName: String
    var sapCode: String
    var versions: [String: ProductVersion]
    var icons: [ProductIcon]

    struct ProductVersion {
        var sapCode: String
        var baseVersion: String
        var productVersion: String
        var apPlatform: String
        var dependencies: [Dependency]
        var buildGuid: String
    }

    struct Dependency {
        var sapCode: String
        var version: String
    }

    struct ProductIcon {
        let size: String
        let url: String

        var dimension: Int {
            let components = size.split(separator: "x")
            if components.count == 2,
               let dimension = Int(components[0]) {
                return dimension
            }
            return 0
        }
    }

    var isValid: Bool {
        return !sapCode.isEmpty && 
               !displayName.isEmpty && 
               !versions.isEmpty
    }

    func getBestIcon() -> ProductIcon? {
        if let icon = icons.first(where: { $0.size == "192x192" }) {
            return icon
        }

        return icons.max(by: { $0.dimension < $1.dimension })
    }
}

struct ParseResult {
    var products: [String: Product]
    var cdn: String
}

class XHXMLParser {

    static func parseProductsXML(xmlData: Data, urlVersion: Int, allowedPlatforms: Set<String>) throws -> ParseResult {
        let xml = try XMLDocument(data: xmlData)

        let prefix = urlVersion == 6 ? "channels/" : ""

        guard let cdn = try xml.nodes(forXPath: "//" + prefix + "channel/cdn/secure").first?.stringValue else {
            throw ParserError.missingCDN
        }
        
        var products: [String: Product] = [:]

        let productNodes = try xml.nodes(forXPath: "//" + prefix + "channel/products/product")

        let parentMap = createParentMap(xml.rootElement())
        
        for productNode in productNodes {
            guard let element = productNode as? XMLElement else { continue }

            let sap = element.attribute(forName: "id")?.stringValue ?? ""
            let parentElement = parentMap[parentMap[element] ?? element]
            let hidden = (parentElement as? XMLElement)?.attribute(forName: "name")?.stringValue != "ccm"
            let displayName = try element.nodes(forXPath: "displayName").first?.stringValue ?? ""
            let productVersion = element.attribute(forName: "version")?.stringValue ?? ""

            if products[sap] == nil {
                let productIcons = try element.nodes(forXPath: "productIcons/icon").compactMap { iconNode -> Product.ProductIcon? in
                    guard let iconElement = iconNode as? XMLElement,
                          let size = iconElement.attribute(forName: "size")?.stringValue,
                          let url = iconElement.stringValue
                    else { return nil }
                    return Product.ProductIcon(size: size, url: url)
                }
                
                products[sap] = Product(
                    id: sap,
                    hidden: hidden,
                    displayName: displayName,
                    sapCode: sap,
                    versions: [:],
                    icons: productIcons
                )
            }

            let platforms = try element.nodes(forXPath: "platforms/platform")
            for platformNode in platforms {
                guard let platform = platformNode as? XMLElement else { continue }
                
                let appPlatform = platform.attribute(forName: "id")?.stringValue ?? ""

                guard let languageSet = try platform.nodes(forXPath: "languageSet").first as? XMLElement else { continue }
                
                let baseVersion = languageSet.attribute(forName: "baseVersion")?.stringValue ?? ""
                var buildGuid = languageSet.attribute(forName: "buildGuid")?.stringValue ?? ""
                let currentProductVersion = productVersion

                if let existingVersion = products[sap]?.versions[productVersion],
                   allowedPlatforms.contains(existingVersion.apPlatform) {
                    continue
                }

                if sap == "APRO" {
                    let baseVersion = productVersion
                    var currentProductVersion = productVersion
                    
                    if urlVersion == 4 || urlVersion == 5 {
                        if let appVersion = try languageSet.nodes(forXPath: "nglLicensingInfo/appVersion").first?.stringValue {
                            currentProductVersion = appVersion
                        }
                    } else if urlVersion == 6 {
                        currentProductVersion = productVersion
                        
                        let builds = try xml.nodes(forXPath: "//builds/build")
                        for build in builds {
                            guard let buildElement = build as? XMLElement,
                                  buildElement.attribute(forName: "id")?.stringValue == sap,
                                  buildElement.attribute(forName: "version")?.stringValue == baseVersion else {
                                continue
                            }
                            break
                        }
                    }

                    buildGuid = try languageSet.nodes(forXPath: "urls/manifestURL").first?.stringValue ?? buildGuid

                    if !buildGuid.isEmpty && allowedPlatforms.contains(appPlatform) {
                        let version = Product.ProductVersion(
                            sapCode: sap,
                            baseVersion: baseVersion,
                            productVersion: currentProductVersion,
                            apPlatform: appPlatform,
                            dependencies: [],
                            buildGuid: buildGuid
                        )
                        
                        products[sap]?.versions[currentProductVersion] = version
                    }
                    continue
                }

                let dependencies = try languageSet.nodes(forXPath: "dependencies/dependency").compactMap { node -> Product.Dependency? in
                    guard let element = node as? XMLElement,
                          let sapCode = try element.nodes(forXPath: "sapCode").first?.stringValue,
                          let version = try element.nodes(forXPath: "baseVersion").first?.stringValue
                    else { return nil }
                    return Product.Dependency(sapCode: sapCode, version: version)
                }

                if !buildGuid.isEmpty && allowedPlatforms.contains(appPlatform) {
                    let version = Product.ProductVersion(
                        sapCode: sap,
                        baseVersion: baseVersion,
                        productVersion: currentProductVersion,
                        apPlatform: appPlatform,
                        dependencies: dependencies,
                        buildGuid: buildGuid
                    )
                    
                    products[sap]?.versions[currentProductVersion] = version
                }
            }
        }

        let validProducts = products.filter { product in
            !product.value.hidden &&
            product.value.isValid &&
            !product.value.versions.isEmpty
        }
        
        return ParseResult(products: validProducts, cdn: cdn)
    }

    private static func createParentMap(_ root: XMLNode?) -> [XMLNode: XMLNode] {
        var parentMap: [XMLNode: XMLNode] = [:]
        
        func traverse(_ node: XMLNode) {
            for child in node.children ?? [] {
                parentMap[child] = node
                traverse(child)
            }
        }
        
        if let root = root {
            traverse(root)
        }
        
        return parentMap
    }
}

enum ParserError: Error {
    case missingCDN
    case invalidXML
    case missingRequired
}

extension XHXMLParser {
    static func parse(xmlString: String, urlVersion: Int, allowedPlatforms: Set<String>) throws -> ParseResult {
        guard let data = xmlString.data(using: .utf8) else {
            throw ParserError.invalidXML
        }
        return try parseProductsXML(xmlData: data, urlVersion: urlVersion, allowedPlatforms: allowedPlatforms)
    }
}
