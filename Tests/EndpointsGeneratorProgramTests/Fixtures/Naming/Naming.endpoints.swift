// endpoints-configuration-version: 1
import EndpointsGeneratorConfig

let namingConfiguration = EndpointsConfiguration(
    accessLevel: .public,
    enumCaseNamingStrategy: .verbatim,
    operationNamingStrategy: .custom { $0.removingPrefix("legacy_").upperCamelCased },
    acronyms: ["ID", "URL"],
    renames: [
        .type("Date"): "CalendarDate",
        .type("東京"): "Tokyo",
        .property("owner_name", in: "pet_record"): "owner",
        .type(.inline(.property("status", in: "pet_record"))): "OrderStatus",
        .enumCase("IN_PROGRESS", in: .inline(.property("status", in: "pet_record"))): "working",
        .parameter("id", in: .query, of: .route(method: .get, path: "/pets/{pet_id}")): "queryIdentifier",
        .parameter("id", in: .header, of: .route(method: .get, path: "/pets/{pet_id}")): "headerIdentifier",
        .environment("Production US"): "production",
    ]
)
