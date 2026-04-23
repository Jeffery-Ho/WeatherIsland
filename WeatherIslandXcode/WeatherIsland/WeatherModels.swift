import Foundation

struct WeatherSnapshot {
    let locationName: String
    let temperature: Int
    let apparentTemperature: Int
    let humidity: Int
    let windSpeed: Int
    let conditionLabel: String
    let icon: String
    let updatedAt: String
    let nextThreeHoursRainHint: String

    static let placeholder = WeatherSnapshot(
        locationName: "正在定位...",
        temperature: 0,
        apparentTemperature: 0,
        humidity: 0,
        windSpeed: 0,
        conditionLabel: "同步中",
        icon: "sun.max.fill",
        updatedAt: "--:--",
        nextThreeHoursRainHint: "未来3小时内不会下雨"
    )
}

struct IPLocationResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let city: String?
    let region: String?
    let country_name: String?
}

struct OpenMeteoResponse: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let precipitation: [Double]
    }

    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let relative_humidity_2m: Double
        let weather_code: Int
        let wind_speed_10m: Double
    }

    let current: Current
    let hourly: Hourly
}
