// swift-tools-version:6.0

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


import PackageDescription

let package = Package(
  name: "google-api-swift-client",
  platforms: [
    .macOS(.v10_15), .iOS(.v15), .tvOS(.v15)
  ],
  products: [
    .executable(
      name: "google-api-swift-generator",
      targets: ["google-api-swift-generator"]
    ),
    .executable(
      name: "google-cli-swift-generator",
      targets: ["google-api-swift-generator"]
    ),
    .library(
      name: "GoogleAPIRuntime",
      targets: ["GoogleAPIRuntime"]
    ),
    .library(
      name: "Discovery",
      targets: ["Discovery"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/googleapis/google-auth-library-swift.git", from: "0.5.3"),
  ],
  targets: [
    .executableTarget(
      name: "google-api-swift-generator",
      dependencies: ["Discovery"]
    ),
    .executableTarget(
      name: "google-cli-swift-generator",
      dependencies: ["Discovery"]
    ),
    .target(
      name: "GoogleAPIRuntime",
      dependencies: [
        .product(name: "OAuth2", package: "google-auth-library-swift")
      ]
    ),
    .target(
      name: "Discovery"
    ),
  ]
)
