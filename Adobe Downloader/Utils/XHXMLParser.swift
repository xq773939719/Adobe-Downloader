//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation

struct ParseResult {
    var products: [String: Sap]
    var cdn: String
}

class XHXMLParser {

    static func parseProductsXML(xmlData: Data) throws -> ParseResult {
        let xml = try XMLDocument(data: xmlData)

        let allowedPlatforms = Set(["osx10-64", "osx10", "macuniversal", "macarm64"])
        guard let cdn = try xml.nodes(forXPath: "//channels/channel/cdn/secure").first?.stringValue else {
            throw ParserError.missingCDN
        }
        // print("parseProductsXML - cdn: \(cdn)")

        var products: [String: Sap] = [:]

        let productNodes = try xml.nodes(forXPath: "//channels/channel/products/product")
        let parentMap = createParentMap(xml.rootElement())
        for productNode in productNodes {
            guard let element = productNode as? XMLElement else { continue }

            let sap = element.attribute(forName: "id")?.stringValue ?? ""
            let parentElement = parentMap[parentMap[element] ?? element]
            let hidden = (parentElement as? XMLElement)?.attribute(forName: "name")?.stringValue != "ccm"
            let displayName = try element.nodes(forXPath: "displayName").first?.stringValue ?? ""
            var productVersion = element.attribute(forName: "version")?.stringValue ?? ""

            if products[sap] == nil {
                let icons = try element.nodes(forXPath: "productIcons/icon").compactMap { node -> Sap.ProductIcon? in
                    guard let element = node as? XMLElement,
                          let size = element.attribute(forName: "size")?.stringValue,
                          let url = element.stringValue else {
                        return nil
                    }
                    return Sap.ProductIcon(size: size, url: url)
                }
                
                products[sap] = Sap(
                    hidden: hidden,
                    displayName: displayName,
                    sapCode: sap,
                    versions: [:],
                    icons: icons
                )
            }

            let platforms = try element.nodes(forXPath: "platforms/platform")
            for platformNode in platforms {
                guard let platform = platformNode as? XMLElement,
                      let languageSet = try platform.nodes(forXPath: "languageSet").first as? XMLElement else { continue }
                
                var baseVersion = languageSet.attribute(forName: "baseVersion")?.stringValue ?? ""
                var buildGuid = languageSet.attribute(forName: "buildGuid")?.stringValue ?? ""
                let appPlatform = platform.attribute(forName: "id")?.stringValue ?? ""
                let dependencies = try languageSet.nodes(forXPath: "dependencies/dependency").compactMap { node -> Sap.Versions.Dependencies? in
                    guard let element = node as? XMLElement,
                          let sapCode = try element.nodes(forXPath: "sapCode").first?.stringValue,
                          let version = try element.nodes(forXPath: "baseVersion").first?.stringValue else {
                        return nil
                    }
                    return Sap.Versions.Dependencies(sapCode: sapCode, version: version)
                }

                if let existingVersion = products[sap]?.versions[productVersion],
                   allowedPlatforms.contains(existingVersion.apPlatform) {
                    break
                }
                
                if sap == "APRO" {
                    baseVersion = productVersion
                    let buildNodes = try xml.nodes(forXPath: "//builds/build")
                    for buildNode in buildNodes {
                        guard let buildElement = buildNode as? XMLElement,
                              buildElement.attribute(forName: "id")?.stringValue == sap,
                              buildElement.attribute(forName: "version")?.stringValue == baseVersion else {
                            continue
                        }
                        if let appVersion = try buildElement.nodes(forXPath: "nglLicensingInfo/appVersion").first?.stringValue {
                            productVersion = appVersion
                            break
                        }
                    }
                    buildGuid = try languageSet.nodes(forXPath: "urls/manifestURL").first?.stringValue ?? ""
                }
                
                if !buildGuid.isEmpty && allowedPlatforms.contains(appPlatform) {
                    let version = Sap.Versions(
                        sapCode: sap,
                        baseVersion: baseVersion,
                        productVersion: productVersion,
                        apPlatform: appPlatform,
                        dependencies: dependencies,
                        buildGuid: buildGuid
                    )
                    products[sap]?.versions[productVersion] = version
                }
            }
        }
        
        return ParseResult(products: products, cdn: cdn)
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
    static func parse(xmlString: String) throws -> ParseResult {
        guard let data = xmlString.data(using: .utf8) else {
            throw ParserError.invalidXML
        }
        return try parseProductsXML(xmlData: data)
    }
}
