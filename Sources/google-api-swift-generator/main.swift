// Copyright 2019 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Discovery

enum ParsingError: Error {
  case topLevelSchemaUnknownType(schemaName: String, type: String)
  case topLevelSchemaArrayDoesNotContainObjects(schemaName: String)
  case arrayDidNotIncludeItems(schemaName: String?)
  case arrayHadUnknownItems(schemaName: String)
  case schemaDidNotIncludeTypeOrRef(schemaName: String)
  case arrayContainedArray(schemaName: String)
  case unknown
}

func createInitLines(baseIndent: Int, parentName: String?, parameters: [String: Schema]) -> String {
  let inputs = parameters
      .sorted(by: { $0.key < $1.key })
      .map { (arg: (key: String, value: Schema)) -> (key: String, type: String) in
        let (key, value) = arg
        let typeName: String
        if let parentName = parentName {
          typeName = "\(parentName.upperCamelCased())_\(key.upperCamelCased())"
        } else {
          typeName = key.upperCamelCased()
        }
        var tmpKey = key.camelCased()
        if tmpKey == "self" {
          tmpKey = "selfRef"
        }
        return (key: "\(tmpKey)", type: "\(value.Type(objectName: typeName))?")
      }
  let inputSignature = "\n" + inputs.map {
    String(repeating: " ", count: 12) + "\($0.key): \($0.type) = nil"
  }.joined(separator: ",\n") + "\n" + String(repeating: " ", count: 8)
  let assignments = inputs.reduce("") { (prev: String, curr: (key: String, type: String)) -> String in
    let nextItem = String(repeating: " ", count: 12) + "self.\(curr.key) = \(curr.key)"
    if prev.isEmpty { return "\n" + nextItem }
    return """
    \(prev)
    \(nextItem)
    """
  }
  return """
      public init (\(inputSignature)) {\(assignments)
          }
  """
}

func createCodingKeys(baseIndent: Int, parentName: String?, parameters: [String: Schema]) -> String {
  let someKeyHasHyphen = parameters.keys.reduce(false) { (prev: Bool, curr: String) -> Bool in
    if prev { return prev }
    return curr.contains("-") || curr.contains(".") || curr.starts(with: "$") || curr.starts(with: "@") || curr == "self"
  }
  guard someKeyHasHyphen else { return "" }
  let cases = parameters
      .sorted(by: { $0.key < $1.key })
      .reduce("") { (prev: String, curr: (key: String, value: Schema)) -> String in
        let explicitValue = curr.key.contains("-") || curr.key.contains(".") || curr.key.starts(with: "$") || curr.key.starts(with: "@") || curr.key == "self"
            ? " = \"\(curr.key)\""
            : ""
        var key = curr.key.camelCased()
        if key == "self" {
          key = "selfRef"
        }
        let nextLine = "case `\(key)`\(explicitValue)"
        if prev.isEmpty { return String(repeating: " ", count: 12) + nextLine }
        return """
        \(prev)
                    \(nextLine)
        """
      }
  return """
          enum CodingKeys : String, CodingKey {
  \(cases)
          }
  """
}

func createArrayType(nextName: String, schema: (key: String, value: Schema), stringUnderConstruction: inout String) throws -> String {
  guard let arrayItems = schema.value.items else {
    throw ParsingError.arrayDidNotIncludeItems(schemaName: schema.key)
  }
  let type: String
  if var ref = arrayItems.ref {
    let escapingNames = ["Type", "Error"]
    if escapingNames.contains(ref) {
      ref = "Custom_" + ref
    }
    type = "[\(ref)]"
  } else if let _ = arrayItems.properties {
    try createNestedObject(parentName: nextName, name: nextName, schema: arrayItems, stringUnderConstruction: &stringUnderConstruction)
    type = "\(schema.value.Type(objectName: nextName))"
  } else if let additionalProperties = arrayItems.additionalProperties {
    try createDynamicNestedObject(parentName: nextName, name: nextName, schema: additionalProperties, stringUnderConstruction: &stringUnderConstruction)
    type = "\(schema.value.Type(objectName: nextName))"
  }
  else if let arrayItemType = arrayItems.type {
    var arrayItemTypeName = ""
    switch arrayItemType {
      case "string": arrayItemTypeName = "String" // todo: perform check for enums.
      case "integer": arrayItemTypeName = "Int"
      case "number": arrayItemTypeName = "Double"
      case "boolean": arrayItemTypeName = "Bool"
      case "array":
        arrayItemTypeName = try createArrayType(nextName: nextName, schema: (key: "\(schema.key)ArrayItem", value: arrayItems), stringUnderConstruction: &stringUnderConstruction)
      default: arrayItemTypeName = "JSONAny"
    }
    type = "[\(arrayItemTypeName)]"
  } else {
    throw ParsingError.arrayHadUnknownItems(schemaName: schema.key)
  }
  return type
}

func createSchemaAssignment(parentName: String?, name: String, schema: (key: String, value: Schema), stringUnderConstruction: inout String) throws -> (key: String, type: String) {
  var key = schema.key.camelCased()
  if key == "self" { key = "selfRef" }
  let type: String
  let nextName = "\(name.upperCamelCased())_\(schema.key.upperCamelCased())"
  if let t = schema.value.type {
    switch t {
      case "object":
        // replace branchs with single route?
        if let additionalProperties = schema.value.additionalProperties {
          let dynamicNextName = schema.value.Type(objectName: nextName)
          try createDynamicNestedObject(parentName: nextName, name: dynamicNextName, schema: additionalProperties, stringUnderConstruction: &stringUnderConstruction)
          type = schema.value.Type(objectName: nextName)
        } else {
          try createNestedObject(parentName: nextName, name: nextName, schema: schema.value, stringUnderConstruction: &stringUnderConstruction)
          type = "\(schema.value.Type(objectName: nextName))"
        }
      case "array":
        type = try createArrayType(nextName: nextName, schema: schema, stringUnderConstruction: &stringUnderConstruction)
      default:
        type = schema.value.Type()
    }
  } else if let ref = schema.value.ref {
      let escapingNames = ["Type", "Error"]
      if escapingNames.contains(ref) {
        type = "Custom_" + ref
      } else {
        type = ref
      }
  } else {
    throw ParsingError.schemaDidNotIncludeTypeOrRef(schemaName: schema.key)
  }
  return (key: key, type: type)
}

func createDynamicNestedObject(parentName: String?, name: String, schema: Schema, stringUnderConstruction: inout String) throws {
  let aliasType: String
  if let type = schema.type, type == "object" {
    try createNestedObject(parentName: (parentName ?? "") + "Item", name: name + "Item", schema: schema, stringUnderConstruction: &stringUnderConstruction)
    aliasType = "[String: \(schema.Type(objectName: name + "Item"))]"
  } else if let type = schema.type, type == "array", let arrayItems = schema.items, arrayItems.type == "object" {
    try createNestedObject(parentName: (parentName ?? "") + "Item", name: name + "Item", schema: schema, stringUnderConstruction: &stringUnderConstruction)
    aliasType = "[String: \(schema.Type(objectName: name + "Item"))]"
  } else {
    aliasType = "[String: \(schema.Type(objectName: name))]"
  }
  // todo: check for string being an enum
  stringUnderConstruction.addLine(indent: 4, "public typealias \(name) = \(aliasType)\n")
}

func createStaticNestedObject(parentName: String?, name: String, schema: Schema, stringUnderConstruction: inout String) throws {
  let currentIndent = 2
  let initializer = createInitLines(baseIndent: currentIndent, parentName: parentName, parameters: schema.properties!)
  let codingKeys = createCodingKeys(baseIndent: currentIndent, parentName: parentName, parameters: schema.properties!)
  var assignments = ""
  for p in schema.properties!.sorted(by: { $0.key.camelCased() < $1.key.camelCased() }) {
    let assignment = try createSchemaAssignment(parentName: parentName, name: name, schema: p, stringUnderConstruction: &stringUnderConstruction)
    assignments.addLine(indent: 8, "public let \(assignment.key): \(assignment.type)?")
  }
  //todo: add comments for class
  let escapingNames = ["Type", "Error"]
  let className = escapingNames.contains(name) ? "Custom_" + name : name
  let def = """
    public final class \(className): Codable, Sendable {
      \(initializer)\(!codingKeys.isEmpty ? "\n\(codingKeys)" : "")
  \(assignments)    }
  
  """
  stringUnderConstruction.addLine(indent: currentIndent, def)
}

func createNestedObject(parentName: String?, name: String, schema: Schema, stringUnderConstruction: inout String) throws {
  if let additionalProperties = schema.additionalProperties {
    try createDynamicNestedObject(parentName: parentName, name: name, schema: additionalProperties, stringUnderConstruction: &stringUnderConstruction)
  } else if let _ = schema.properties {
    try createStaticNestedObject(parentName: parentName, name: name, schema: schema, stringUnderConstruction: &stringUnderConstruction)
  } else {
    // object has no dynamic properties, and no static properties. Can't infer what it is. Typealias to JSONAny
    let aliasDef = "public typealias \(name) = JSONAny\n"
    stringUnderConstruction.addLine(indent: 4, aliasDef)
  }
}

func createCodingKeys(baseIndent: Int, parameters: [String: Schema]) -> String {
  let someKeyHasHyphen = parameters.keys.reduce(false) { (prev: Bool, curr: String) -> Bool in
    if prev { return prev }
    return curr.contains("-")
  }
  guard someKeyHasHyphen else { return "" }
  var currentIndent = baseIndent
  var enumDeclaration = ""
  enumDeclaration.addLine(indent: currentIndent, "enum CodingKeys : String, CodingKey {")
  currentIndent += 2
  for p in parameters.sorted(by: { $0.key < $1.key }) {
    let explicitValue = p.key.contains("-") ? " = \"\(p.key)\"" : ""
    enumDeclaration.addLine(indent: currentIndent, "case `\(p.key.camelCased())`\(explicitValue)")
  }
  currentIndent -= 2
  enumDeclaration.addLine(indent: currentIndent, "}")
  return enumDeclaration
}

extension Discovery.Method {
  
  func ParametersTypeDeclaration(resource : String, method : String) -> String {
    var s = ""
    s.addLine()
    guard let parameters = parameters else { return "" } // todo: check: should this throw an error or return func with no args?
    
    let initializer = createInitLines(baseIndent: 4, parentName: nil, parameters: parameters)
    let codingKeys = createCodingKeys(baseIndent: 4, parentName: nil, parameters: parameters)
    var classProperties = ""
    for p in parameters.sorted(by:  { $0.key < $1.key }) {
      classProperties.addLine(indent:8, "public let \(p.key.camelCased()): \(p.value.Type())?")
    }

    let filteredQueryParameterItems = parameters
      .sorted(by: { $0.key < $1.key })
      .filter { if let location = $0.value.location { return location == "query" } else { return false } }

    let queryParameterItems = filteredQueryParameterItems
        .map { return String(repeating: " ", count: 16) + "\"\($0.key.camelCased())\"" }
        .joined(separator: ",\n") + ",\n" + String(repeating: " ", count: 12)
    let queryParametersDef = """
            public func queryParameters() -> [String] {
                [\(!filteredQueryParameterItems.isEmpty ? "\n\(queryParameterItems)" : "")]
            }
    """

    let filteredPathParameterItems = parameters
      .sorted(by: { $0.key < $1.key })
      .filter { if let location = $0.value.location { return location == "path" } else { return false } }

    let pathParameterItems = filteredPathParameterItems
      .map { return String(repeating: " ", count: 16) + "\"\($0.key.camelCased())\"" }
      .joined(separator: ",\n") + ",\n" + String(repeating: " ", count: 12)
    let pathParametersDef = """
            public func pathParameters() -> [String] {
                [\(!filteredPathParameterItems.isEmpty ? "\n\(pathParameterItems)" : "")]
            }
    """
    
    return """
        public final class \(ParametersTypeName(resource:resource, method:method)): Parameterizable, Sendable {
        \(initializer)
    \(codingKeys)
    \(classProperties)
    \(queryParametersDef)
    \(pathParametersDef)
        }
    
    """
  }
}

extension Discovery.Resource {
  func generate(name: String) -> String {
    var s = ""
    if let methods = self.methods {
      for m in methods.sorted(by:  { $0.key < $1.key }) {
        s.addLine()
        if m.value.HasParameters() {
          s += m.value.ParametersTypeDeclaration(resource:name, method:m.key)
        }
        let methodName = name.camelCased() + "_" + m.key.upperCamelCased()
        s.addLine()
        s.addLine(indent:4, "public func \(methodName) (")

        var arguments = [String]()

        if m.value.HasRequest() {
          arguments.append("request: \(m.value.RequestTypeName())")
        }
        if m.value.HasParameters() {
          arguments.append("parameters: \(m.value.ParametersTypeName(resource:name, method:m.key))")
        }

        let returnSignature = if m.value.HasResponse() {
          ") async throws -> \(m.value.ResponseTypeName()) {"
        } else {
          ") async throws {"
        }

        if arguments.isEmpty {
          s.addLine(returnSignature)
        } else {
          for (index, argument) in arguments.enumerated() {
            s.addLine(indent: 8, argument + (index < arguments.count - 1 ? "," : ""))
          }
          s.addLine(indent: 4, returnSignature)
        }

        var bodyArguments = [String]()

        var path = ""
        if m.value.path != nil {
          path = m.value.path!
        }

        bodyArguments.append("method: \"\(m.value.httpMethod!)\"")
        bodyArguments.append("path: \"\(path)\"")

        if m.value.HasRequest() {
          bodyArguments.append("request: request")
        }
        if m.value.HasParameters() {
          bodyArguments.append("parameters: parameters")
        }

        s.addLine(indent: 8, "try await perform(")
        for (index, argument) in bodyArguments.enumerated() {
          s.addLine(indent: 12, argument + (index < bodyArguments.count - 1 ? "," : ""))
        }
        s.addLine(indent:8, ")")
        s.addLine(indent:4, "}")
        s.addLine()
      }
    }
    if let resources = self.resources {
      for r in resources.sorted(by:  { $0.key < $1.key }) {
        s += r.value.generate(name: name + "_" + r.key)
      }
    }
    return s
  }
}

extension Discovery.Service {
  func generate() throws -> String {
    guard let schemas = schemas else {
      return ""
    }
    var generatedSchemas = ""
    for schema in schemas.sorted(by:  { $0.key < $1.key }) {
      switch schema.value.type {
      case "object":
        try createNestedObject(parentName: schema.key,
                           name: schema.key.camelCased(),
                           schema: schema.value,
                           stringUnderConstruction: &generatedSchemas)
      case "array":
        guard let itemsSchema = schema.value.items else {
          throw ParsingError.topLevelSchemaArrayDoesNotContainObjects(schemaName: schema.key)
        }
        if let ref = itemsSchema.ref {
          generatedSchemas.addLine(indent: 4, "public typealias \(schema.key) = [\(ref)]")
        } else {
          generatedSchemas.addLine(indent:2, "public typealias \(schema.key) = [\(schema.key)Item]")
          generatedSchemas.addLine()
          generatedSchemas.addLine(indent:2, "public class \(schema.key)Item : Codable {")
          if let properties = itemsSchema.properties {
            let initializer = createInitLines(baseIndent: 4, parentName: nil, parameters: properties)
            generatedSchemas.addTextWithoutLinebreak(initializer)
            let codingKeys = createCodingKeys(baseIndent: 4, parentName: nil, parameters: properties)
            generatedSchemas.addLine(codingKeys)
            for p in properties.sorted(by: { $0.key < $1.key }) {
              generatedSchemas.addLine(indent:4, "public let \(p.key.camelCased()) : \(p.value.Type())?")
            }
          }
          generatedSchemas.addLine("}")
        }
      case "any":
        generatedSchemas.addLine(indent: 2, "public typealias `\(schema.key)` = JSONAny")
      default:
        throw ParsingError.topLevelSchemaUnknownType(schemaName: schema.key, type: schema.value.type ?? "nil - unknown type")
      }
    }
    
    var generatedResources = ""
    if let resources = resources {
      for r in resources.sorted(by:  { $0.key < $1.key }) {
        generatedResources += r.value.generate(name: r.key)
      }
    }
    
    return """
    \(Discovery.License)
    
    import Foundation
    import OAuth2
    import GoogleAPIRuntime
    
    public final class \(self.name.capitalized()): Service, @unchecked Sendable {
        public init(tokenProvider: TokenProvider) {
            super.init(tokenProvider, "\(self.baseUrl)")
        }
    
    \(generatedSchemas)
    
    \(generatedResources)
    }
    """
  }
}

func main() throws {
  let arguments = CommandLine.arguments
  if (arguments.count > 1) {
    let discoveryFileURL = URL(fileURLWithPath: arguments[1])
    try processDiscoveryDocument(url: discoveryFileURL, name: discoveryFileURL.deletingPathExtension().lastPathComponent)
  } else {
    try interactiveServiceGeneration()
  }
}

func processDiscoveryDocument(url: URL, name: String) throws {
  let data = try Data(contentsOf: url)
  let decoder = JSONDecoder()
  do {
    let service = try decoder.decode(Service.self, from: data)
    let code = try service.generate()
    let fileURL = URL(fileURLWithPath: name).appendingPathExtension("swift")
    try code.write(to: fileURL, atomically: true, encoding: .utf8)
    print("wrote \(fileURL.path)")
  } catch {
    print("error \(error)\n")
  }
}

func interactiveServiceGeneration() throws {
  let data = try Data(contentsOf: URL(string: "https://www.googleapis.com/discovery/v1/apis")!)
  let decoder = JSONDecoder()
  let directoryList = try decoder.decode(DirectoryList.self, from: data)
  var map : [Int:DirectoryItem] = [:]
  var i = 1
  for item in directoryList.items.filter({ $0.preferred }) {
    map[i] = item
    let istr = String.init(describing: i)
    let padding = String(repeatElement(" ", count: 3 - istr.count))
    print("\(padding + istr)) \(item.title)")
    i += 1
  }
  var directoryItem: DirectoryItem? = map[248]
//  repeat {
//    print("Please enter the number corresponding to the service or 0 to exit")
//    print("> ", terminator: "")
//    let input = readLine()
//    if input == "0" {
//      return
//    }
//    if let i = Int(input!), input != nil {
//      directoryItem = map[i]
//    }
//  } while directoryItem == nil
  try processDiscoveryDocument(url: directoryItem!.discoveryRestUrl, name: directoryItem!.id.replacingOccurrences(of: ":", with: ""))
}

do {
  try main()
} catch (let error) {
  print("ERROR: \(error)\n")
}
