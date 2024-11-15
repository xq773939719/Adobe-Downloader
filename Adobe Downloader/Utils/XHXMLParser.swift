//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation

struct ParseResult {
    var products: [String: Sap]
    var cdn: String
}

class XHXMLParser {
    private static let xpathCache = [
        "cdn": "//channels/channel/cdn/secure",
        "products": "//channels/channel/products/product",
        "icons": "productIcons/icon",
        "platforms": "platforms/platform",
        "languageSet": "languageSet",
        "dependencies": "dependencies/dependency",
        "sapCode": "sapCode",
        "baseVersion": "baseVersion",
        "builds": "//builds/build",
        "appVersion": "nglLicensingInfo/appVersion",
        "manifestURL": "urls/manifestURL"
    ]

    private static func createParentMap(_ root: XMLNode?) -> [XMLNode: XMLNode] {
        var parentMap = [XMLNode: XMLNode](minimumCapacity: 500)
        
        func traverse(_ node: XMLNode) {
            guard let children = node.children else { return }
            for child in children {
                parentMap[child] = node
                traverse(child)
            }
        }
        
        if let root = root {
            traverse(root)
        }
        return parentMap
    }

    static func parseProductsXML(xmlData: Data) throws -> ParseResult {
        let xml = try XMLDocument(data: xmlData)

        guard let cdn = try xml.nodes(forXPath: xpathCache["cdn"]!).first?.stringValue else {
            throw ParserError.missingCDN
        }

        var products = [String: Sap](minimumCapacity: 100)
        
        let productNodes = try xml.nodes(forXPath: xpathCache["products"]!)
        let parentMap = createParentMap(xml.rootElement())

        for productNode in productNodes {
            guard let element = productNode as? XMLElement else { continue }
            
            let sap = element.attribute(forName: "id")?.stringValue ?? ""
            let parentElement = parentMap[parentMap[element] ?? element]
            let hidden = (parentElement as? XMLElement)?.attribute(forName: "name")?.stringValue != "ccm"

            let displayName = try element.nodes(forXPath: "displayName").first?.stringValue ?? ""
            var productVersion = element.attribute(forName: "version")?.stringValue ?? ""
            
            if products[sap] == nil {
                let icons = try element.nodes(forXPath: xpathCache["icons"]!).compactMap { node -> Sap.ProductIcon? in
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

            let platforms = try element.nodes(forXPath: xpathCache["platforms"]!)
            for platformNode in platforms {
                guard let platform = platformNode as? XMLElement,
                      let languageSet = try platform.nodes(forXPath: xpathCache["languageSet"]!).first as? XMLElement else { continue }
                
                var baseVersion = languageSet.attribute(forName: "baseVersion")?.stringValue ?? ""
                var buildGuid = languageSet.attribute(forName: "buildGuid")?.stringValue ?? ""
                let appPlatform = platform.attribute(forName: "id")?.stringValue ?? ""

                if let existingVersion = products[sap]?.versions[productVersion],
                   existingVersion.apPlatform == "macuniversal" {
                    break
                }

                let dependencies = try languageSet.nodes(forXPath: xpathCache["dependencies"]!).compactMap { node -> Sap.Versions.Dependencies? in
                    guard let element = node as? XMLElement else { return nil }
                    let sapCode = try element.nodes(forXPath: "sapCode").first?.stringValue ?? ""
                    let version = try element.nodes(forXPath: "baseVersion").first?.stringValue ?? ""
                    guard !sapCode.isEmpty, !version.isEmpty else { return nil }
                    return Sap.Versions.Dependencies(sapCode: sapCode, version: version)
                }

                if sap == "APRO" {
                    baseVersion = productVersion
                    if let buildNode = try xml.nodes(forXPath: xpathCache["builds"]!).first(where: { node in
                        guard let element = node as? XMLElement else { return false }
                        return element.attribute(forName: "id")?.stringValue == sap &&
                               element.attribute(forName: "version")?.stringValue == baseVersion
                    }) as? XMLElement {
                        if let appVersion = try buildNode.nodes(forXPath: xpathCache["appVersion"]!).first?.stringValue {
                            productVersion = appVersion
                        }
                    }
                    buildGuid = try languageSet.nodes(forXPath: xpathCache["manifestURL"]!).first?.stringValue ?? ""
                }
                
                if !buildGuid.isEmpty {
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
