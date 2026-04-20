import CoreLocation
import Foundation

struct OpenAIChatToolDefinition: Encodable, Sendable {
    struct FunctionDefinition: Encodable, Sendable {
        let name: String
        let description: String
        let parameters: JSONSchema
        let strict: Bool
    }

    let type: String
    let function: FunctionDefinition

    init(name: String, description: String, parameters: JSONSchema, strict: Bool = true) {
        self.type = "function"
        self.function = FunctionDefinition(
            name: name,
            description: description,
            parameters: parameters,
            strict: strict
        )
    }
}

struct JSONSchema: Encodable, Sendable {
    enum SchemaType: Sendable {
        case single(String)
        case multiple([String])
    }

    let type: SchemaType?
    let description: String?
    let properties: [String: JSONSchema]?
    let required: [String]?
    let additionalProperties: Bool?
    let enumValues: [String]?

    init(
        type: SchemaType? = nil,
        description: String? = nil,
        properties: [String: JSONSchema]? = nil,
        required: [String]? = nil,
        additionalProperties: Bool? = nil,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
        self.enumValues = enumValues
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case properties
        case required
        case additionalProperties
        case enumValues = "enum"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch type {
        case .single(let value):
            try container.encode(value, forKey: .type)
        case .multiple(let values):
            try container.encode(values, forKey: .type)
        case nil:
            break
        }

        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(properties, forKey: .properties)
        try container.encodeIfPresent(required, forKey: .required)
        try container.encodeIfPresent(additionalProperties, forKey: .additionalProperties)
        try container.encodeIfPresent(enumValues, forKey: .enumValues)
    }
}

struct BuiltinChatToolExecutor: Sendable {
    private struct EmptyArguments: Decodable, Sendable {}

    private struct WeatherArguments: Decodable, Sendable {
        let locationQuery: String?
        let useCurrentLocation: Bool
    }

    private struct WeatherForecastArguments: Decodable, Sendable {
        let locationQuery: String?
        let useCurrentLocation: Bool
        let startDayOffset: Int
        let dayCount: Int
    }

    private struct DateTimePayload: Encodable, Sendable {
        let ok = true
        let iso8601: String
        let dateText: String
        let timeText: String
        let weekdayText: String
        let calendarDate: String
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let second: Int
        let timeZoneIdentifier: String
        let utcOffset: String
    }

    private struct LocationPayload: Encodable, Sendable {
        let ok = true
        let latitude: Double
        let longitude: Double
        let horizontalAccuracyMeters: Double
        let displayName: String
        let locality: String?
        let administrativeArea: String?
        let country: String?
        let isoCountryCode: String?
        let timeZoneIdentifier: String?
        let observedAtISO8601: String
    }

    private struct WeatherPayload: Encodable, Sendable {
        let ok = true
        let source: String
        let locationName: String
        let latitude: Double
        let longitude: Double
        let timezone: String
        let observedAtISO8601: String
        let weatherSummary: String
        let temperatureCelsius: Double?
        let apparentTemperatureCelsius: Double?
        let relativeHumidityPercent: Double?
        let precipitationMillimeters: Double?
        let windSpeedKilometersPerHour: Double?
        let windDirectionDegrees: Double?
    }

    private struct WeatherForecastDayPayload: Encodable, Sendable {
        let date: String
        let weekdayText: String
        let weatherSummary: String
        let maxTemperatureCelsius: Double?
        let minTemperatureCelsius: Double?
        let precipitationProbabilityPercent: Double?
        let precipitationMillimeters: Double?
        let maxWindSpeedKilometersPerHour: Double?
    }

    private struct WeatherForecastPayload: Encodable, Sendable {
        let ok = true
        let source: String
        let locationName: String
        let latitude: Double
        let longitude: Double
        let timezone: String
        let generatedAtISO8601: String
        let startDayOffset: Int
        let dayCount: Int
        let dailyForecasts: [WeatherForecastDayPayload]
    }

    private struct ToolFailurePayload: Encodable, Sendable {
        let ok = false
        let error: String
    }

    private struct OpenMeteoResponse: Decodable, Sendable {
        struct Current: Decodable, Sendable {
            let time: String
            let temperature2m: Double?
            let apparentTemperature: Double?
            let relativeHumidity2m: Double?
            let precipitation: Double?
            let weatherCode: Int?
            let windSpeed10m: Double?
            let windDirection10m: Double?

            private enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case relativeHumidity2m = "relative_humidity_2m"
                case precipitation
                case weatherCode = "weather_code"
                case windSpeed10m = "wind_speed_10m"
                case windDirection10m = "wind_direction_10m"
            }
        }

        struct Daily: Decodable, Sendable {
            let time: [String]
            let weatherCode: [Int?]
            let temperature2mMax: [Double?]
            let temperature2mMin: [Double?]
            let precipitationProbabilityMax: [Double?]
            let precipitationSum: [Double?]
            let windSpeed10mMax: [Double?]

            private enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
                case precipitationSum = "precipitation_sum"
                case windSpeed10mMax = "wind_speed_10m_max"
            }
        }

        let latitude: Double
        let longitude: Double
        let timezone: String
        let current: Current?
        let daily: Daily?
    }

    enum ToolError: LocalizedError {
        case locationServicesDisabled
        case locationPermissionDenied
        case locationUnavailable
        case geocodingFailed
        case invalidArguments
        case weatherUnavailable

        var errorDescription: String? {
            switch self {
            case .locationServicesDisabled:
                return "设备未开启定位服务。"
            case .locationPermissionDenied:
                return "应用没有定位权限，请在系统设置中允许“使用 App 时”定位。"
            case .locationUnavailable:
                return "暂时无法获取当前位置，请稍后再试。"
            case .geocodingFailed:
                return "无法识别地点，请换一种更明确的地点描述。"
            case .invalidArguments:
                return "工具参数无效。"
            case .weatherUnavailable:
                return "天气服务暂时不可用，请稍后重试。"
            }
        }
    }

    private static let maxForecastDays = 10
    private let jsonDecoder: JSONDecoder
    private let apiDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    init() {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.jsonDecoder = decoder
        self.apiDecoder = JSONDecoder()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.jsonEncoder = encoder
    }

    var toolDefinitions: [OpenAIChatToolDefinition] {
        [
            OpenAIChatToolDefinition(
                name: "get_current_datetime",
                description: "获取当前真实日期和时间。凡是用户询问今天几月几号、星期几、现在几点、当前时间、当前日期或时区时，都必须优先调用这个工具，不要凭记忆回答。",
                parameters: JSONSchema(
                    type: .single("object"),
                    properties: [:],
                    required: [],
                    additionalProperties: false
                )
            ),
            OpenAIChatToolDefinition(
                name: "get_current_location",
                description: "获取设备当前地理位置和地名。当用户询问“我在哪里”“我当前的位置”“我附近有什么”“去哪里玩”或问题依赖当前所在地时调用。这个工具需要设备定位权限。",
                parameters: JSONSchema(
                    type: .single("object"),
                    properties: [:],
                    required: [],
                    additionalProperties: false
                )
            ),
            OpenAIChatToolDefinition(
                name: "get_current_weather",
                description: "获取实时天气。若用户问当前位置天气或说“我这里”，将 use_current_location 设为 true；若用户明确给出城市、区县或地址，将原始地点文本放到 location_query，并将 use_current_location 设为 false。",
                parameters: JSONSchema(
                    type: .single("object"),
                    properties: [
                        "location_query": JSONSchema(
                            type: .multiple(["string", "null"]),
                            description: "用户提供的城市、区县、地址或地标原始文本。若使用当前定位则传 null。"
                        ),
                        "use_current_location": JSONSchema(
                            type: .single("boolean"),
                            description: "是否使用设备当前定位来查询天气。"
                        )
                    ],
                    required: ["location_query", "use_current_location"],
                    additionalProperties: false
                )
            ),
            OpenAIChatToolDefinition(
                name: "get_weather_forecast",
                description: "获取未来天气预报。凡是用户询问明天、后天、周末、下周、未来几天的天气、温度、降雨，或问某天是否适合出门、适合去哪里玩时，优先调用这个工具。若用户没给地点但问题依赖当前位置，请将 use_current_location 设为 true。start_day_offset 以今天为 0、明天为 1；day_count 表示连续查询几天，范围 1 到 10。",
                parameters: JSONSchema(
                    type: .single("object"),
                    properties: [
                        "location_query": JSONSchema(
                            type: .multiple(["string", "null"]),
                            description: "用户提供的城市、区县、地址或地标原始文本。若使用当前定位则传 null。"
                        ),
                        "use_current_location": JSONSchema(
                            type: .single("boolean"),
                            description: "是否使用设备当前定位来查询天气预报。"
                        ),
                        "start_day_offset": JSONSchema(
                            type: .single("integer"),
                            description: "从今天开始偏移多少天。今天为 0，明天为 1，后天为 2。"
                        ),
                        "day_count": JSONSchema(
                            type: .single("integer"),
                            description: "连续查询几天的预报，范围 1 到 10。"
                        )
                    ],
                    required: ["location_query", "use_current_location", "start_day_offset", "day_count"],
                    additionalProperties: false
                )
            )
        ]
    }

    func execute(named toolName: String, argumentsJSON: String) async -> String {
        do {
            switch toolName {
            case "get_current_datetime":
                _ = try decode(EmptyArguments.self, from: argumentsJSON)
                return try encode(makeDateTimePayload())
            case "get_current_location":
                _ = try decode(EmptyArguments.self, from: argumentsJSON)
                let location = try await DeviceLocationProvider.shared.currentLocationSnapshot()
                return try encode(
                    LocationPayload(
                        latitude: location.latitude,
                        longitude: location.longitude,
                        horizontalAccuracyMeters: location.horizontalAccuracyMeters,
                        displayName: location.displayName,
                        locality: location.locality,
                        administrativeArea: location.administrativeArea,
                        country: location.country,
                        isoCountryCode: location.isoCountryCode,
                        timeZoneIdentifier: location.timeZoneIdentifier,
                        observedAtISO8601: Self.iso8601String(from: location.observedAt)
                    )
                )
            case "get_current_weather":
                let arguments = try decode(WeatherArguments.self, from: argumentsJSON)
                return try await encode(makeWeatherPayload(arguments: arguments))
            case "get_weather_forecast":
                let arguments = try decode(WeatherForecastArguments.self, from: argumentsJSON)
                return try await encode(makeWeatherForecastPayload(arguments: arguments))
            default:
                return failureJSON(message: "未知工具：\(toolName)")
            }
        } catch {
            return failureJSON(message: error.localizedDescription)
        }
    }

    private func makeDateTimePayload() -> DateTimePayload {
        let now = Date()
        let timeZone = TimeZone.current
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: timeZone,
            from: now
        )

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy年M月d日"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm:ss"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.timeZone = timeZone
        weekdayFormatter.dateFormat = "EEEE"

        let offsetSeconds = timeZone.secondsFromGMT(for: now)
        let hours = offsetSeconds / 3600
        let minutes = abs(offsetSeconds % 3600) / 60
        let utcOffset = String(format: "%+.2d:%02d", hours, minutes)

        return DateTimePayload(
            iso8601: Self.iso8601String(from: now, timeZone: timeZone),
            dateText: dateFormatter.string(from: now),
            timeText: timeFormatter.string(from: now),
            weekdayText: weekdayFormatter.string(from: now),
            calendarDate: String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0),
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            timeZoneIdentifier: timeZone.identifier,
            utcOffset: utcOffset
        )
    }

    private func makeWeatherPayload(arguments: WeatherArguments) async throws -> WeatherPayload {
        let location = try await resolveLocation(
            useCurrentLocation: arguments.useCurrentLocation,
            locationQuery: arguments.locationQuery
        )

        let weather = try await fetchWeather(latitude: location.latitude, longitude: location.longitude)
        guard let current = weather.current else {
            throw ToolError.weatherUnavailable
        }

        return WeatherPayload(
            source: "Open-Meteo",
            locationName: location.displayName,
            latitude: weather.latitude,
            longitude: weather.longitude,
            timezone: weather.timezone,
            observedAtISO8601: current.time,
            weatherSummary: weatherSummary(for: current.weatherCode),
            temperatureCelsius: current.temperature2m,
            apparentTemperatureCelsius: current.apparentTemperature,
            relativeHumidityPercent: current.relativeHumidity2m,
            precipitationMillimeters: current.precipitation,
            windSpeedKilometersPerHour: current.windSpeed10m,
            windDirectionDegrees: current.windDirection10m
        )
    }

    private func makeWeatherForecastPayload(arguments: WeatherForecastArguments) async throws -> WeatherForecastPayload {
        guard arguments.startDayOffset >= 0,
              arguments.dayCount > 0,
              arguments.dayCount <= Self.maxForecastDays else {
            throw ToolError.invalidArguments
        }

        let forecastDaysToFetch = arguments.startDayOffset + arguments.dayCount
        guard forecastDaysToFetch <= Self.maxForecastDays else {
            throw ToolError.invalidArguments
        }

        let location = try await resolveLocation(
            useCurrentLocation: arguments.useCurrentLocation,
            locationQuery: arguments.locationQuery
        )
        let weather = try await fetchForecast(
            latitude: location.latitude,
            longitude: location.longitude,
            forecastDays: forecastDaysToFetch
        )

        guard let daily = weather.daily else {
            throw ToolError.weatherUnavailable
        }

        let timeZone = TimeZone(identifier: weather.timezone) ?? .current
        let endIndex = arguments.startDayOffset + arguments.dayCount
        let dailyForecasts = (arguments.startDayOffset..<endIndex).compactMap { index -> WeatherForecastDayPayload? in
            guard let date = daily.time[safe: index] else { return nil }

            return WeatherForecastDayPayload(
                date: date,
                weekdayText: weekdayText(for: date, timeZone: timeZone),
                weatherSummary: weatherSummary(for: daily.weatherCode[safe: index].flatMap { $0 }),
                maxTemperatureCelsius: daily.temperature2mMax[safe: index].flatMap { $0 },
                minTemperatureCelsius: daily.temperature2mMin[safe: index].flatMap { $0 },
                precipitationProbabilityPercent: daily.precipitationProbabilityMax[safe: index].flatMap { $0 },
                precipitationMillimeters: daily.precipitationSum[safe: index].flatMap { $0 },
                maxWindSpeedKilometersPerHour: daily.windSpeed10mMax[safe: index].flatMap { $0 }
            )
        }

        guard dailyForecasts.isEmpty == false else {
            throw ToolError.weatherUnavailable
        }

        return WeatherForecastPayload(
            source: "Open-Meteo",
            locationName: location.displayName,
            latitude: weather.latitude,
            longitude: weather.longitude,
            timezone: weather.timezone,
            generatedAtISO8601: Self.iso8601String(from: Date(), timeZone: timeZone),
            startDayOffset: arguments.startDayOffset,
            dayCount: dailyForecasts.count,
            dailyForecasts: dailyForecasts
        )
    }

    private func geocode(locationQuery: String) async throws -> DeviceLocationSnapshot {
        let placemarks = try await CLGeocoder().geocodeAddressStringAsync(locationQuery)
        guard let placemark = placemarks.first,
              let location = placemark.location else {
            throw ToolError.geocodingFailed
        }

        return DeviceLocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            displayName: formattedPlacemarkName(for: placemark, fallback: locationQuery),
            locality: placemark.locality,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country,
            isoCountryCode: placemark.isoCountryCode,
            timeZoneIdentifier: placemark.timeZone?.identifier,
            observedAt: Date()
        )
    }

    private func resolveLocation(
        useCurrentLocation: Bool,
        locationQuery: String?
    ) async throws -> DeviceLocationSnapshot {
        if useCurrentLocation {
            return try await DeviceLocationProvider.shared.currentLocationSnapshot()
        }

        if let locationQuery = locationQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
           locationQuery.isEmpty == false {
            return try await geocode(locationQuery: locationQuery)
        }

        throw ToolError.invalidArguments
    }

    private func fetchWeather(latitude: Double, longitude: Double) async throws -> OpenMeteoResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m,wind_direction_10m"
            ),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components?.url else {
            throw ToolError.weatherUnavailable
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            throw ToolError.weatherUnavailable
        }

        return try apiDecoder.decode(OpenMeteoResponse.self, from: data)
    }

    private func fetchForecast(latitude: Double, longitude: Double, forecastDays: Int) async throws -> OpenMeteoResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max"
            ),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components?.url else {
            throw ToolError.weatherUnavailable
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            throw ToolError.weatherUnavailable
        }

        return try apiDecoder.decode(OpenMeteoResponse.self, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let data = Data(json.utf8)
        return try jsonDecoder.decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ payload: T) throws -> String {
        let data = try jsonEncoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    private func failureJSON(message: String) -> String {
        (try? encode(ToolFailurePayload(error: message))) ?? "{\"ok\":false,\"error\":\"\(message)\"}"
    }

    private func weatherSummary(for weatherCode: Int?) -> String {
        switch weatherCode {
        case 0:
            return "晴"
        case 1:
            return "大部晴朗"
        case 2:
            return "局部多云"
        case 3:
            return "阴"
        case 45, 48:
            return "有雾"
        case 51, 53, 55:
            return "毛毛雨"
        case 56, 57:
            return "冻毛毛雨"
        case 61:
            return "小雨"
        case 63:
            return "中雨"
        case 65:
            return "大雨"
        case 66, 67:
            return "冻雨"
        case 71:
            return "小雪"
        case 73:
            return "中雪"
        case 75:
            return "大雪"
        case 77:
            return "雪粒"
        case 80:
            return "阵雨"
        case 81, 82:
            return "强阵雨"
        case 85, 86:
            return "阵雪"
        case 95:
            return "雷暴"
        case 96, 99:
            return "强雷暴伴冰雹"
        default:
            return "天气状况未知"
        }
    }

    private static func iso8601String(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func weekdayText(for dateString: String, timeZone: TimeZone) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = timeZone
        parser.dateFormat = "yyyy-MM-dd"

        guard let date = parser.date(from: dateString) else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

}

private struct DeviceLocationSnapshot: Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double
    let displayName: String
    let locality: String?
    let administrativeArea: String?
    let country: String?
    let isoCountryCode: String?
    let timeZoneIdentifier: String?
    let observedAt: Date
}

@MainActor
private final class DeviceLocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = DeviceLocationProvider()

    private let locationManager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocationSnapshot() async throws -> DeviceLocationSnapshot {
        guard CLLocationManager.locationServicesEnabled() else {
            throw BuiltinChatToolExecutor.ToolError.locationServicesDisabled
        }

        try await ensureAuthorization()
        let location = try await requestLocation()
        let placemarks = try await CLGeocoder().reverseGeocodeLocationAsync(location)
        let placemark = placemarks.first

        return DeviceLocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            displayName: placemark.map { formattedPlacemarkName(for: $0, fallback: "当前位置") } ?? "当前位置",
            locality: placemark?.locality,
            administrativeArea: placemark?.administrativeArea,
            country: placemark?.country,
            isoCountryCode: placemark?.isoCountryCode,
            timeZoneIdentifier: placemark?.timeZone?.identifier,
            observedAt: Date()
        )
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let authorizationContinuation else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            self.authorizationContinuation = nil
            authorizationContinuation.resume()
        case .denied, .restricted:
            self.authorizationContinuation = nil
            authorizationContinuation.resume(throwing: BuiltinChatToolExecutor.ToolError.locationPermissionDenied)
        case .notDetermined:
            break
        @unknown default:
            self.authorizationContinuation = nil
            authorizationContinuation.resume(throwing: BuiltinChatToolExecutor.ToolError.locationPermissionDenied)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let locationContinuation else { return }
        self.locationContinuation = nil

        if let location = locations.last {
            locationContinuation.resume(returning: location)
        } else {
            locationContinuation.resume(throwing: BuiltinChatToolExecutor.ToolError.locationUnavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let locationContinuation else { return }
        self.locationContinuation = nil
        locationContinuation.resume(throwing: error)
    }

    private func ensureAuthorization() async throws {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return
        case .denied, .restricted:
            throw BuiltinChatToolExecutor.ToolError.locationPermissionDenied
        case .notDetermined:
            if authorizationContinuation != nil {
                throw BuiltinChatToolExecutor.ToolError.locationUnavailable
            }

            try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
        @unknown default:
            throw BuiltinChatToolExecutor.ToolError.locationPermissionDenied
        }
    }

    private func requestLocation() async throws -> CLLocation {
        if let lastLocation = locationManager.location {
            return lastLocation
        }

        if locationContinuation != nil {
            throw BuiltinChatToolExecutor.ToolError.locationUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }
}

private extension CLGeocoder {
    func geocodeAddressStringAsync(_ addressString: String) async throws -> [CLPlacemark] {
        try await withCheckedThrowingContinuation { continuation in
            geocodeAddressString(addressString) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: placemarks ?? [])
            }
        }
    }

    func reverseGeocodeLocationAsync(_ location: CLLocation) async throws -> [CLPlacemark] {
        try await withCheckedThrowingContinuation { continuation in
            reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: placemarks ?? [])
            }
        }
    }
}

private func formattedPlacemarkName(for placemark: CLPlacemark, fallback: String) -> String {
    let rawComponents: [String?] = [
        placemark.name,
        placemark.locality,
        placemark.administrativeArea,
        placemark.country
    ]

    let components = rawComponents
        .compactMap { (value: String?) -> String? in
            guard let value, value.isEmpty == false else { return nil }
            return value
        }

    return components.isEmpty ? fallback : components.joined(separator: " ")
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
