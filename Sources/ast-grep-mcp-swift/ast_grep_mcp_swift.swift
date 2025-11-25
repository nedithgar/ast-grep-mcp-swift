import Foundation
import ArgumentParser
import MCP
import Yams

private let version = "0.1.0"
enum DebugContext {
    @TaskLocal static var enabled = false
}

private func debugLog(_ message: () -> String) {
    guard DebugContext.enabled else { return }
    if let data = ("[debug] " + message() + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

private func resolveConfigPath(cliConfig: String?) throws -> String? {
    if let cliConfig {
        guard FileManager.default.fileExists(atPath: cliConfig) else {
            throw ValidationError("Config file '\(cliConfig)' does not exist")
        }
        return cliConfig
    }

    if let envPath = ProcessInfo.processInfo.environment["AST_GREP_CONFIG"] {
        guard FileManager.default.fileExists(atPath: envPath) else {
            throw ValidationError("Config file '\(envPath)' specified in AST_GREP_CONFIG does not exist")
        }
        return envPath
    }

    return nil
}

// MARK: - JSON Schema helpers

private func stringSchema(description: String?, allowed: [String]? = nil, defaultValue: String? = nil) -> Value {
    var dict: [String: Value] = ["type": "string"]
    if let description {
        dict["description"] = .string(description)
    }
    if let allowed {
        dict["enum"] = .array(allowed.map { .string($0) })
    }
    if let defaultValue {
        dict["default"] = .string(defaultValue)
    }
    return .object(dict)
}

private func integerSchema(description: String?, defaultValue: Int? = nil) -> Value {
    var dict: [String: Value] = ["type": "integer"]
    if let description {
        dict["description"] = .string(description)
    }
    if let defaultValue {
        dict["default"] = .int(defaultValue)
    }
    return .object(dict)
}

private func objectSchema(properties: [String: Value], required: [String]) -> Value {
    .object([
        "type": "object",
        "properties": .object(properties),
        "required": .array(required.map { .string($0) }),
        "additionalProperties": .bool(false)
    ])
}

// MARK: - Utilities

private struct CommandResult {
    let stdout: String
    let stderr: String
}

/// Thread-safe accumulator for pipe output.
final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }
}

private func runCommand(_ args: [String], input: String? = nil) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args

    debugLog {
        var parts = ["Executing command:"]
        parts.append(args.joined(separator: " "))
        if input != nil {
            parts.append("(stdin provided)")
        }
        return parts.joined(separator: " ")
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let stdoutBuffer = OutputBuffer()
    let stderrBuffer = OutputBuffer()

    let group = DispatchGroup()
    group.enter()
    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
            handle.readabilityHandler = nil
            group.leave()
            return
        }
        stdoutBuffer.append(data)
    }

    group.enter()
    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
            handle.readabilityHandler = nil
            group.leave()
            return
        }
        stderrBuffer.append(data)
    }

    var stdinPipe: Pipe?
    if input != nil {
        let pipe = Pipe()
        process.standardInput = pipe
        stdinPipe = pipe
    }

    do {
        try process.run()
    } catch {
        throw MCPError.internalError("Command '" + (args.first ?? "") + "' failed to start: \(error)")
    }

    if let input, let stdinPipe {
        stdinPipe.fileHandleForWriting.write(Data(input.utf8))
        stdinPipe.fileHandleForWriting.closeFile()
    }

    process.waitUntilExit()
    group.wait()

    let stdout = String(decoding: stdoutBuffer.snapshot(), as: UTF8.self)
    let stderr = String(decoding: stderrBuffer.snapshot(), as: UTF8.self)

    debugLog { "Command exit status: \(process.terminationStatus)" }
    if !stdout.isEmpty {
        debugLog { "stdout (first 200 chars): \(stdout.prefix(200))" }
    }
    if !stderr.isEmpty {
        debugLog { "stderr (first 200 chars): \(stderr.prefix(200))" }
    }

    if process.terminationStatus != 0 {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        throw MCPError.internalError("Command \(args.joined(separator: " ")) failed with exit code \(process.terminationStatus): \(message.isEmpty ? "(no error output)" : message)")
    }

    return CommandResult(stdout: stdout, stderr: stderr)
}

private func runAstGrep(configPath: String?, subcommand: String, args: [String], input: String? = nil) throws -> CommandResult {
    var fullArgs = ["ast-grep", subcommand]
    if let configPath {
        fullArgs += ["--config", configPath]
    }
    fullArgs += args
    debugLog { "ast-grep command args: \(fullArgs.joined(separator: " "))" }
    return try runCommand(fullArgs, input: input)
}

private func decodeMatches(_ jsonString: String) throws -> [[String: Any]] {
    let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    guard let data = trimmed.data(using: .utf8) else { return [] }
    guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw MCPError.internalError("Unexpected ast-grep JSON output")
    }
    return array
}

private func encodeJSON(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func formatMatchesAsText(_ matches: [[String: Any]]) -> String {
    guard !matches.isEmpty else { return "" }

    let blocks: [String] = matches.map { match in
        let file = match["file"] as? String ?? ""
        let range = match["range"] as? [String: Any]
        let start = ((range?["start"] as? [String: Any])?["line"] as? Int ?? 0) + 1
        let end = ((range?["end"] as? [String: Any])?["line"] as? Int ?? 0) + 1
        let text = trimTrailingWhitespace(match["text"] as? String ?? "")
        let header = start == end ? "\(file):\(start)" : "\(file):\(start)-\(end)"
        return "\(header)\n\(text)"
    }

    return blocks.joined(separator: "\n\n")
}

private func trimTrailingWhitespace(_ text: String) -> String {
    var result = text
    while let last = result.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.contains(last) {
        result.removeLast()
    }
    return result
}

private func jsonResourceContent(_ value: Any) throws -> Tool.Content {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    let base64 = data.base64EncodedString()
    let text = String(decoding: data, as: UTF8.self)
    return .resource(uri: "data:application/json;base64,\(base64)", mimeType: "application/json", text: text)
}

private func getSupportedLanguages(configPath: String?) -> [String] {
    var languages: [String] = [
        "bash", "c", "cpp", "csharp", "css", "elixir", "go", "haskell",
        "html", "java", "javascript", "json", "jsx", "kotlin", "lua",
        "nix", "php", "python", "ruby", "rust", "scala", "solidity",
        "swift", "tsx", "typescript", "yaml"
    ]

    if let path = configPath, FileManager.default.fileExists(atPath: path) {
        if let yamlString = try? String(contentsOfFile: path, encoding: .utf8),
           let loaded = try? Yams.load(yaml: yamlString) as? [String: Any],
           let custom = loaded["customLanguages"] as? [String: Any] {
            languages.append(contentsOf: custom.keys)
        }
    }

    return Array(Set(languages)).sorted()
}

// MARK: - Argument helpers

private func requiredString(_ args: [String: Value]?, key: String) throws -> String {
    guard let value = args?[key]?.stringValue, !value.isEmpty else {
        throw MCPError.invalidParams("Missing required string argument '\(key)'")
    }
    return value
}

private func optionalString(_ args: [String: Value]?, key: String, default defaultValue: String = "") -> String {
    args?[key]?.stringValue ?? defaultValue
}

private func intArgument(_ args: [String: Value]?, key: String, default defaultValue: Int = 0) throws -> Int {
    if let intValue = args?[key]?.intValue {
        return intValue
    }
    if let doubleValue = args?[key]?.doubleValue {
        return Int(doubleValue)
    }
    if let string = args?[key]?.stringValue, let parsed = Int(string) {
        return parsed
    }
    return defaultValue
}

// MARK: - Tool implementations

private func dumpSyntaxTreeTool(_ args: [String: Value]?, languages: [String], configPath: String?) throws -> CallTool.Result {
    _ = languages // currently used only for description; retained to mirror Python signature
    let code = try requiredString(args, key: "code")
    let language = try requiredString(args, key: "language")
    let format = optionalString(args, key: "format", default: "cst")

    guard ["pattern", "cst", "ast"].contains(format) else {
        throw MCPError.invalidParams("Invalid format: \(format). Expected pattern, ast, or cst")
    }

    // Run ast-grep; debug output is written to stderr
    let result = try runAstGrep(
        configPath: configPath,
        subcommand: "run",
        args: ["--pattern", code, "--lang", language, "--debug-query=\(format)"],
        input: nil
    )

    let output = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    return .init(content: [.text(output.isEmpty ? result.stdout : output)], isError: false)
}

private func testMatchCodeRuleTool(_ args: [String: Value]?, configPath: String?) throws -> CallTool.Result {
    let code = try requiredString(args, key: "code")
    let ruleYaml = try requiredString(args, key: "yaml")

    let result = try runAstGrep(
        configPath: configPath,
        subcommand: "scan",
        args: ["--inline-rules", ruleYaml, "--json", "--stdin"],
        input: code
    )

    let matches = try decodeMatches(result.stdout)
    if matches.isEmpty {
        throw MCPError.internalError("No matches found for the given code and rule. Try adding `stopBy: end` to inside/has rules.")
    }

    let jsonText = try encodeJSON(matches)
    return .init(content: [.text(jsonText)], isError: false)
}

private func findCodeTool(_ args: [String: Value]?, configPath: String?) throws -> CallTool.Result {
    let projectFolder = try requiredString(args, key: "project_folder")
    let pattern = try requiredString(args, key: "pattern")
    let language = optionalString(args, key: "language")
    let maxResults = try intArgument(args, key: "max_results", default: 0)
    let outputFormat = optionalString(args, key: "output_format", default: "text")

    guard ["text", "json"].contains(outputFormat) else {
        throw MCPError.invalidParams("Invalid output_format: \(outputFormat). Use 'text' or 'json'.")
    }

    var arguments = ["--pattern", pattern]
    if !language.isEmpty {
        arguments += ["--lang", language]
    }

    let result = try runAstGrep(
        configPath: configPath,
        subcommand: "run",
        args: arguments + ["--json", projectFolder],
        input: nil
    )

    var matches = try decodeMatches(result.stdout)
    let total = matches.count
    if maxResults > 0 && total > maxResults {
        matches = Array(matches.prefix(maxResults))
    }

    if outputFormat == "text" {
        if matches.isEmpty {
            return .init(content: [.text("No matches found")], isError: false)
        }

        let text = formatMatchesAsText(matches)
        var header = "Found \(matches.count) matches"
        if maxResults > 0 && total > maxResults {
            header += " (showing first \(maxResults) of \(total))"
        }
        return .init(content: [.text("\(header):\n\n\(text)")], isError: false)
    } else {
        let content = try jsonResourceContent(matches)
        return .init(content: [content], isError: false)
    }
}

private func findCodeByRuleTool(_ args: [String: Value]?, configPath: String?) throws -> CallTool.Result {
    let projectFolder = try requiredString(args, key: "project_folder")
    let yamlRule = try requiredString(args, key: "yaml")
    let maxResults = try intArgument(args, key: "max_results", default: 0)
    let outputFormat = optionalString(args, key: "output_format", default: "text")

    guard ["text", "json"].contains(outputFormat) else {
        throw MCPError.invalidParams("Invalid output_format: \(outputFormat). Use 'text' or 'json'.")
    }

    let result = try runAstGrep(
        configPath: configPath,
        subcommand: "scan",
        args: ["--inline-rules", yamlRule, "--json", projectFolder],
        input: nil
    )

    var matches = try decodeMatches(result.stdout)
    let total = matches.count
    if maxResults > 0 && total > maxResults {
        matches = Array(matches.prefix(maxResults))
    }

    if outputFormat == "text" {
        if matches.isEmpty {
            return .init(content: [.text("No matches found")], isError: false)
        }

        let text = formatMatchesAsText(matches)
        var header = "Found \(matches.count) matches"
        if maxResults > 0 && total > maxResults {
            header += " (showing first \(maxResults) of \(total))"
        }
        return .init(content: [.text("\(header):\n\n\(text)")], isError: false)
    } else {
        let content = try jsonResourceContent(matches)
        return .init(content: [content], isError: false)
    }
}

// MARK: - Tool registration

private func buildTools(languages: [String]) -> [Tool] {
    let languageDescription = "The language of the code. Supported: \(languages.joined(separator: ", "))"

    let dumpSyntaxTree = Tool(
        name: "dump_syntax_tree",
        description: "Dump code's syntax structure or a query's pattern structure using ast-grep",
        inputSchema: objectSchema(
            properties: [
                "code": stringSchema(description: "The code you need"),
                "language": stringSchema(description: languageDescription),
                "format": stringSchema(
                    description: "Code dump format", allowed: ["pattern", "ast", "cst"], defaultValue: "cst")
            ],
            required: ["code", "language"]
        )
    )

    let testMatchCodeRule = Tool(
        name: "test_match_code_rule",
        description: "Test code against an ast-grep YAML rule",
        inputSchema: objectSchema(
            properties: [
                "code": stringSchema(description: "The code to test against the rule"),
                "yaml": stringSchema(description: "The ast-grep YAML rule. Must include id, language, rule fields.")
            ],
            required: ["code", "yaml"]
        )
    )

    let findCode = Tool(
        name: "find_code",
        description: "Find code in a project folder that matches a given ast-grep pattern",
        inputSchema: objectSchema(
            properties: [
                "project_folder": stringSchema(description: "Absolute path to the project folder"),
                "pattern": stringSchema(description: "The ast-grep pattern to search for"),
                "language": stringSchema(description: "Language (optional). If not provided, detected from file extensions.", defaultValue: ""),
                "max_results": integerSchema(description: "Maximum results to return", defaultValue: 0),
                "output_format": stringSchema(description: "'text' or 'json'", allowed: ["text", "json"], defaultValue: "text")
            ],
            required: ["project_folder", "pattern"]
        )
    )

    let findCodeByRule = Tool(
        name: "find_code_by_rule",
        description: "Find code using an ast-grep YAML rule in a project folder",
        inputSchema: objectSchema(
            properties: [
                "project_folder": stringSchema(description: "Absolute path to the project folder"),
                "yaml": stringSchema(description: "The ast-grep YAML rule. Must include id, language, rule fields."),
                "max_results": integerSchema(description: "Maximum results to return", defaultValue: 0),
                "output_format": stringSchema(description: "'text' or 'json'", allowed: ["text", "json"], defaultValue: "text")
            ],
            required: ["project_folder", "yaml"]
        )
    )

    return [dumpSyntaxTree, testMatchCodeRule, findCode, findCodeByRule]
}

private func registerHandlers(server: Server, languages: [String], configPath: String?) async {
    await server.withMethodHandler(ListTools.self) { _ in
        debugLog { "Handling list_tools" }
        return .init(tools: buildTools(languages: languages))
    }

    await server.withMethodHandler(CallTool.self) { params in
        do {
            debugLog {
                let keys = params.arguments?.keys.joined(separator: ", ") ?? "<none>"
                return "Handling tool call: \(params.name) (args: \(keys))"
            }
            switch params.name {
            case "dump_syntax_tree":
                return try dumpSyntaxTreeTool(params.arguments, languages: languages, configPath: configPath)
            case "test_match_code_rule":
                return try testMatchCodeRuleTool(params.arguments, configPath: configPath)
            case "find_code":
                return try findCodeTool(params.arguments, configPath: configPath)
            case "find_code_by_rule":
                return try findCodeByRuleTool(params.arguments, configPath: configPath)
            default:
                throw MCPError.methodNotFound("Unknown tool \(params.name)")
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .init(content: [.text(message)], isError: true)
        }
    }
}

// MARK: - Entry point

@main
struct AstGrepMCPServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ast-grep-mcp-swift",
        abstract: "ast-grep MCP Server - Provides structural code search via Model Context Protocol",
        discussion: "Environment: AST_GREP_CONFIG path to sgconfig.yaml (overridden by --config)"
    )

    @Flag(name: [.short, .long, .customLong("debug")], help: "Print verbose debug logs to stderr")
    var verbose = false

    @Option(name: .long, help: "Path to sgconfig.yaml file for customizing ast-grep behavior")
    var config: String?

    mutating func run() async throws {
        try await DebugContext.$enabled.withValue(verbose) {
            if verbose {
                debugLog { "Verbose debug logging enabled" }
            }

            let configPath = try resolveConfigPath(cliConfig: config)
            debugLog { "Using config path: \(configPath ?? "<none>")" }
            let languages = getSupportedLanguages(configPath: configPath)
            debugLog { "Loaded supported languages: \(languages.joined(separator: ", "))" }

            let server = Server(
                name: "ast-grep",
                version: version,
                instructions: "Expose ast-grep CLI tools over MCP",
                capabilities: .init(tools: .init(listChanged: true))
            )

            await registerHandlers(server: server, languages: languages, configPath: configPath)

            let transport = StdioTransport()
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
        }
    }
}
