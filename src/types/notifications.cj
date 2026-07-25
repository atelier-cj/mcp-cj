package mcp.types

import jsonvalue.*
import stdx.encoding.json.stream.*
import std.collection.HashMap

public enum LoggingLevel <: JsonSerializable & JsonDeserializable<LoggingLevel> {
    | Alert
    | Critical
    | Debug
    | Emergency
    | Error
    | Info
    | Notice
    | Warning

    public func toJson(w: JsonWriter): Unit {
        match (this) {
            case LoggingLevel.Alert => w.writeValue("alert")
            case LoggingLevel.Critical => w.writeValue("critical")
            case LoggingLevel.Debug => w.writeValue("debug")
            case LoggingLevel.Emergency => w.writeValue("emergency")
            case LoggingLevel.Error => w.writeValue("error")
            case LoggingLevel.Info => w.writeValue("info")
            case LoggingLevel.Notice => w.writeValue("notice")
            case LoggingLevel.Warning => w.writeValue("warning")
        }
    }

    public static func fromJson(r: JsonReader): LoggingLevel {
        match (r.readValue<String>()) {
            case "alert" => LoggingLevel.Alert
            case "critical" => LoggingLevel.Critical
            case "debug" => LoggingLevel.Debug
            case "emergency" => LoggingLevel.Emergency
            case "error" => LoggingLevel.Error
            case "info" => LoggingLevel.Info
            case "notice" => LoggingLevel.Notice
            case "warning" => LoggingLevel.Warning
            case v => throw Exception("Invalid LoggingLevel: ${v}")
        }
    }
}

public class CancelledNotificationParams <: JsonSerializable & JsonDeserializable<CancelledNotificationParams> {
    public var requestId: JsonValue = JsonValue.Number(0.0)
    public var reason: ?String = None

    public init() {}
    public init(requestId: JsonValue, reason!: ?String = None) {
        this.requestId = requestId
        this.reason = reason
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("requestId")
        this.requestId.toJson(w)
        if (let Some(v) <- this.reason) { w.writeName("reason").writeValue(v) }
        w.endObject()
    }

    public static func fromJson(r: JsonReader): CancelledNotificationParams {
        let res = CancelledNotificationParams()
        fromJsonObject(r,
            ("requestId", {=> res.requestId = JsonValue.fromJson(r)}),
            ("reason", {=> res.reason = r.readValue<Option<String>>()})
        )
        res
    }
}

public class ProgressNotificationParams <: JsonSerializable & JsonDeserializable<ProgressNotificationParams> {
    public var progressToken: JsonValue = JsonValue.String("")
    public var progress: Float64 = 0.0
    public var total: ?Float64 = None
    public var message: ?String = None

    public init() {}
    public init(progressToken: JsonValue, progress: Float64, total!: ?Float64 = None, message!: ?String = None) {
        this.progressToken = progressToken
        this.progress = progress
        this.total = total
        this.message = message
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("progressToken")
        this.progressToken.toJson(w)
        w.writeName("progress").writeValue(this.progress)
        if (let Some(v) <- this.total) { w.writeName("total").writeValue(v) }
        if (let Some(v) <- this.message) { w.writeName("message").writeValue(v) }
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ProgressNotificationParams {
        let res = ProgressNotificationParams()
        fromJsonObject(r,
            ("progressToken", {=> res.progressToken = JsonValue.fromJson(r)}),
            ("progress", {=> res.progress = r.readValue<Float64>()}),
            ("total", {=> res.total = r.readValue<Option<Float64>>()}),
            ("message", {=> res.message = r.readValue<Option<String>>()})
        )
        res
    }
}

public class LoggingMessageNotificationParams <: JsonSerializable & JsonDeserializable<LoggingMessageNotificationParams> {
    public var level: LoggingLevel = LoggingLevel.Info
    public var data: JsonValue = JsonValue.Null
    public var logger: ?String = None

    public init() {}
    public init(level: LoggingLevel, data: JsonValue, logger!: ?String = None) {
        this.level = level
        this.data = data
        this.logger = logger
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("level").writeValue(this.level)
        w.writeName("data")
        this.data.toJson(w)
        if (let Some(v) <- this.logger) { w.writeName("logger").writeValue(v) }
        w.endObject()
    }

    public static func fromJson(r: JsonReader): LoggingMessageNotificationParams {
        let res = LoggingMessageNotificationParams()
        fromJsonObject(r,
            ("level", {=> res.level = r.readValue<LoggingLevel>()}),
            ("data", {=> res.data = JsonValue.fromJson(r)}),
            ("logger", {=> res.logger = r.readValue<Option<String>>()})
        )
        res
    }
}
