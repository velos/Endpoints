//
//  GenerateEndpointsPlugin.swift
//  
//
//  Created by Zac White on 9/29/22.
//

import PackagePlugin
import Foundation

@main
struct GenerateEndpointsPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // Locate generation tool.
        let generationToolFile = try context.tool(named: "generate-endpoints").path
        print("generator: \(generationToolFile)")
    }
}
