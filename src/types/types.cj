package mcp.types

import encoding.json.stream.*
import std.collection.HashMap
import std.io.ByteBuffer
import std.deriving.*

public const LastProtocolVersion = "2024-11-05"
public const JSONRPCVersion = "2.0"
public const PARSE_ERROR = -32700
public const INVALID_REQUEST = -32600
public const METHOD_NOT_FOUND = -32601
public const INVALID_PARAMS = -32602
public const INTERNAL_ERROR = -32603
