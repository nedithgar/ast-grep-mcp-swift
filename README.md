# ast-grep MCP Server (Swift)

An experimental [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) server written in Swift that provides AI assistants with powerful structural code search capabilities using [ast-grep](https://ast-grep.github.io/).

## Overview

This MCP server enables AI assistants (like Cursor, Claude Desktop, etc.) to search and analyze codebases using Abstract Syntax Tree (AST) pattern matching rather than simple text-based search. By leveraging ast-grep's structural search capabilities, AI can:

- Find code patterns based on syntax structure, not just text matching
- Search for specific programming constructs (functions, classes, imports, etc.)
- Write and test complex search rules using YAML configuration
- Debug and visualize AST structures for better pattern development

## Prerequisites

1. **Install ast-grep**: Follow [ast-grep installation guide](https://ast-grep.github.io/guide/quick-start.html#installation)
   ```bash
   # macOS
   brew install ast-grep
   nix-shell -p ast-grep
   cargo install ast-grep --locked
   ```

2. **Swift toolchain**: Swift 6.2 (or Xcode 26+) to build/run the server

3. **MCP-compatible client**: Such as Cursor, Claude Desktop, or other MCP clients

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/ast-grep/ast-grep-mcp-swift.git
   cd ast-grep-mcp-swift
   ```

2. Build once (downloads SwiftPM deps like MCP Swift SDK and Yams):
   ```bash
   swift build
   ```

3. Verify ast-grep installation:
   ```bash
   ast-grep --version
   ```

## Running

Launch the MCP server over stdio:

```bash
swift run ast-grep-mcp-swift --config /absolute/path/to/sgconfig.yaml
```

You can omit `--config` if you rely on defaults or the `AST_GREP_CONFIG` environment variable.

## Configuration

### For Cursor

Add to your MCP settings (usually in `.cursor-mcp/settings.json`):

```json
{
  "mcpServers": {
    "ast-grep": {
      "command": "swift",
      "args": ["run", "ast-grep-mcp-swift", "--config", "/absolute/path/to/sgconfig.yaml"],
      "env": {}
    }
  }
}
```

### For Claude Desktop

Add to your Claude Desktop MCP configuration:

```json
{
  "mcpServers": {
    "ast-grep": {
      "command": "swift",
      "args": ["run", "ast-grep-mcp-swift", "--config", "/absolute/path/to/sgconfig.yaml"],
      "env": {}
    }
  }
}
```

### Custom ast-grep Configuration

The MCP server supports using a custom `sgconfig.yaml` file to configure ast-grep behavior.
See the [ast-grep configuration documentation](https://ast-grep.github.io/guide/project/project-config.html) for details on the config file format.

You can provide the config file in two ways (in order of precedence):

1. **Command-line argument**: `--config /path/to/sgconfig.yaml`
2. **Environment variable**: `AST_GREP_CONFIG=/path/to/sgconfig.yaml`

## Usage

You can attach your own ast-grep rule docs to your MCP client; the server tools (`dump_syntax_tree`, `test_match_code_rule`) help you iterate quickly.

## Features

The server provides four main tools for code analysis:

### 🔍 `dump_syntax_tree`
Visualize the Abstract Syntax Tree structure of code snippets. Essential for understanding how to write effective search patterns.

**Use cases:**
- Debug why a pattern isn't matching
- Understand the AST structure of target code
- Learn ast-grep pattern syntax

### 🧪 `test_match_code_rule`
Test ast-grep YAML rules against code snippets before applying them to larger codebases.

**Use cases:**
- Validate rules work as expected
- Iterate on rule development
- Debug complex matching logic

### 🎯 `find_code`
Search codebases using simple ast-grep patterns for straightforward structural matches.

**Parameters:**
- `max_results`: Limit number of complete matches returned (default: unlimited)
- `output_format`: Choose between `"text"` (default, ~75% fewer tokens) or `"json"` (full metadata)

**Text Output Format:**
```
Found 2 matches:

path/to/file.py:10-15
def example_function():
    # function body
    return result

path/to/file.py:20-22
def another_function():
    pass
```

**Use cases:**
- Find function calls with specific patterns
- Locate variable declarations
- Search for simple code constructs

### 🚀 `find_code_by_rule`
Advanced codebase search using complex YAML rules that can express sophisticated matching criteria.

**Parameters:**
- `max_results`: Limit number of complete matches returned (default: unlimited)
- `output_format`: Choose between `"text"` (default, ~75% fewer tokens) or `"json"` (full metadata)

**Use cases:**
- Find nested code structures
- Search with relational constraints (inside, has, precedes, follows)
- Complex multi-condition searches


## Usage Examples

### Basic Pattern Search

Use Query:

> Find all console.log statements

AI will generate rules like:

```yaml
id: find-console-logs
language: javascript
rule:
  pattern: console.log($$$)
```

### Complex Rule Example

User Query:
> Find async functions that use await

AI will generate rules like:

```yaml
id: async-with-await
language: javascript
rule:
  all:
    - kind: function_declaration
    - has:
        pattern: async
    - has:
        pattern: await $EXPR
        stopBy: end
```

## Supported Languages

ast-grep supports many programming languages including:
- JavaScript/TypeScript
- Python
- Rust
- Go
- Java
- C/C++
- C#
- And many more...

For a complete list of built-in supported languages, see the [ast-grep language support documentation](https://ast-grep.github.io/reference/languages.html).

You can also add support for custom languages through the `sgconfig.yaml` configuration file. See the [custom language guide](https://ast-grep.github.io/guide/project/project-config.html#languagecustomlanguage) for details.

## Troubleshooting

### Common Issues

1. **"Command not found" errors**: Ensure ast-grep is installed and in your PATH
2. **No matches found**: Try adding `stopBy: end` to relational rules
3. **Pattern not matching**: Use `dump_syntax_tree` to understand the AST structure
4. **Permission errors**: Ensure the server has read access to target directories

## Contributing

This is an experimental project. Issues and pull requests are welcome! Built as a Swift port of the original Python server: https://github.com/ast-grep/ast-grep-mcp.

## Related Projects

- [ast-grep](https://ast-grep.github.io/) - The core structural search tool
- [Model Context Protocol](https://modelcontextprotocol.io/) - The protocol this server implements
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) - Swift implementation used by this server
- [Codemod MCP](https://docs.codemod.com/model-context-protocol) - Gives AI assistants tools like tree-sitter AST and node types, ast-grep instructions (YAML and JS ast-grep), and Codemod CLI commands to easily build, publish, and run ast-grep based codemods.
