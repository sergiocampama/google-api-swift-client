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
import OAuth2

enum GoogleAPIRuntimeError: Error {
  case missingPathParameter(String)
  case invalidResponseFromServer
}

public protocol Parameterizable {
  func queryParameters() -> [String]
  func pathParameters() -> [String]
  func query() -> [String: String]
  func path(pattern: String) throws -> String
}

extension Connection {
  @discardableResult
  public func performRequest(
    method: String,
    urlString: String,
    parameters: [String: String],
    body: Data!
  ) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      do {
        try self.performRequest(
          method: method,
          urlString: urlString,
          parameters: parameters,
          body: body
        ) { data, response, error in
          if let error {
            continuation.resume(throwing: error)
          } else if let data {
            continuation.resume(returning: data)
          }
        }
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}

extension Parameterizable {
  public func query() -> [String:String] {
    var q : [String:String] = [:]
    let mirror = Mirror(reflecting: self)
    for p in queryParameters() {
      for child in mirror.children {
        if child.label == p {
          switch child.value {
          case let s as String:
            q[p] = s
          case let i as Int:
            q[p] = "\(i)"
          case Optional<Any>.none:
            continue
          default:
            print("failed to handle \(p) \(child.value)")
          }
          
        }
      }
    }
    return q
  }
  public func path(pattern: String) throws -> String {
    var pattern = pattern
    let mirror = Mirror(reflecting: self)
    for p in pathParameters() {
      for child in mirror.children {
        if child.label == p {
          switch child.value {
          case let s as String:
            pattern = pattern.replacingOccurrences(of: "{"+p+"}", with: s)
          case Optional<Any>.none:
            throw GoogleAPIRuntimeError.missingPathParameter(p)            
          default:
            print("failed to handle \(p) \(child.value)")
          }
        }
      }
    }
    return pattern
  }
}

// general connection helper
open class Service: NSObject {
  var connection : Connection
  var base : String
  
  public init(_ tokenProvider : TokenProvider, _ base : String) {
    self.connection = Connection(provider:tokenProvider)
    self.base = base
  }
  
  func convertResponse<Z: Decodable>(_ data : Data) throws -> Z {
    let json = try JSONSerialization.jsonObject(with: data, options: [])
    let decoder = JSONDecoder()
    if let json = json as? [String: Any] {
      if let errorPayload = json["error"] as? [String: Any],
        let code = errorPayload["code"] as? Int {
          throw NSError(
            domain: "GoogleAPIRuntime",
            code: code,
            userInfo: errorPayload
          )
      } else if let payload = json["data"] {
        // remove the "data" wrapper that is used with some APIs (e.g. translate)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        return try decoder.decode(Z.self, from: payloadData)
      }
    }
    return try decoder.decode(Z.self, from: data)
  }
  
  public func perform<Z: Decodable>(method: String, path: String) async throws -> Z {
    let responseData = try await connection.performRequest(
      method: method,
      urlString: base + path,
      parameters: [:],
      body: nil
    )
    return try self.convertResponse(responseData)
  }
  
  public func perform<X: Encodable, Z: Decodable>(
    method : String,
    path : String,
    request : X
  ) async throws -> Z {
    let encoder = JSONEncoder()
    let requestData = try encoder.encode(request)
    let responseData = try await connection.performRequest(
      method: method,
      urlString: base + path,
      parameters: [:],
      body: requestData
    )
    return try self.convertResponse(responseData)
  }
  
  public func perform<Y: Parameterizable, Z: Decodable>(
    method : String,
    path : String,
    parameters : Y
  ) async throws -> Z {
    let responseData = try await connection.performRequest(
      method: method,
      urlString: base + parameters.path(pattern: path),
      parameters: parameters.query(),
      body: nil
    )
    return try self.convertResponse(responseData)
  }
  
  public func perform<X: Encodable, Y: Parameterizable, Z: Decodable>(
    method : String,
    path : String,
    request : X,
    parameters : Y
  ) async throws -> Z {
    let encoder = JSONEncoder()
    let requestData = try encoder.encode(request)
    let responseData = try await connection.performRequest(
      method: method,
      urlString: base + parameters.path(pattern: path),
      parameters: parameters.query(),
      body: requestData
    )
    return try self.convertResponse(responseData)
  }
  
  public func perform<X: Encodable, Y: Parameterizable>(
    method : String,
    path : String,
    request : X,
    parameters : Y
  ) async throws {
    let encoder = JSONEncoder()
    let requestData = try encoder.encode(request)
    try await connection.performRequest(
      method: method,
      urlString: base + parameters.path(pattern: path),
      parameters: parameters.query(),
      body: requestData
    )
  }
  
  public func perform(
    method : String,
    path : String,
    completion : @escaping(Error?) -> ()
  ) async throws {
    try await connection.performRequest(
      method: method,
      urlString: base + path,
      parameters: [:],
      body: nil
    )
  }

  public func perform<X: Encodable>(
    method : String,
    path : String,
    request : X
  ) async throws {
    let encoder = JSONEncoder()
    let requestData = try encoder.encode(request)
    try await connection.performRequest(
      method: method,
      urlString: base + path,
      parameters: [:],
      body: requestData
    )
  }
  
  public func perform<Y: Parameterizable>(
    method : String,
    path : String,
    parameters : Y
  ) async throws {
    try await connection.performRequest(
      method: method,
      urlString: base + parameters.path(pattern: path),
      parameters: parameters.query(),
      body: nil
    )
  }
}
