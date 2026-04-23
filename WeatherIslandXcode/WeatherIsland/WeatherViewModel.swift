import Foundation
import CoreLocation
import Contacts

@MainActor
final class WeatherViewModel: NSObject, ObservableObject {
    @Published var snapshot = WeatherSnapshot.placeholder
    @Published var isRefreshing = false

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var latestLocation: CLLocation?
    private var latestPlaceName: String?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 50
    }

    func start() {
        requestLocationPermissionIfNeeded()
    }

    func refreshWeather() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            defer {
                Task { @MainActor in
                    self.isRefreshing = false
                }
            }

            do {
                let location = try await resolveLocation()
                latestLocation = location

                async let weatherTask = fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                async let placeTask = reverseGeocode(location)

                let weather = try await weatherTask
                let placeName = (try? await placeTask) ?? latestPlaceName ?? "当前位置"
                latestPlaceName = placeName

                let info = Self.weatherInfo(for: weather.current.weather_code)
                let rainHint = Self.nextThreeHoursRainHint(from: weather)
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"

                await MainActor.run {
                    self.snapshot = WeatherSnapshot(
                        locationName: placeName,
                        temperature: Int(weather.current.temperature_2m.rounded()),
                        apparentTemperature: Int(weather.current.apparent_temperature.rounded()),
                        humidity: Int(weather.current.relative_humidity_2m.rounded()),
                        windSpeed: Int(weather.current.wind_speed_10m.rounded()),
                        conditionLabel: info.label,
                        icon: info.icon,
                        updatedAt: formatter.string(from: Date()),
                        nextThreeHoursRainHint: rainHint
                    )
                }
            } catch let error as CLError {
                await MainActor.run {
                    self.handleLocationError(error)
                }
            } catch {
                await MainActor.run {
                    self.snapshot = WeatherSnapshot(
                        locationName: latestPlaceName ?? "天气不可用",
                        temperature: 0,
                        apparentTemperature: 0,
                        humidity: 0,
                        windSpeed: 0,
                        conditionLabel: "未连接",
                        icon: "wifi.exclamationmark",
                        updatedAt: "--:--",
                        nextThreeHoursRainHint: "未来3小时内不会下雨"
                    )
                }
            }
        }
    }

    private func requestLocationPermissionIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            Task {
                try? await requestAuthorizationIfNeeded()
            }
        default:
            break
        }
    }

    private func resolveLocation() async throws -> CLLocation {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let latestLocation,
               abs(latestLocation.timestamp.timeIntervalSinceNow) < 180 {
                return latestLocation
            }
            return try await requestSingleLocation()
        case .notDetermined:
            try await requestAuthorizationIfNeeded()
            return try await requestSingleLocation()
        case .denied, .restricted:
            throw CLError(.denied)
        @unknown default:
            throw CLError(.locationUnknown)
        }
    }

    private func requestAuthorizationIfNeeded() async throws {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return
        case .denied, .restricted:
            throw CLError(.denied)
        case .notDetermined:
            try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
        @unknown default:
            throw CLError(.locationUnknown)
        }
    }

    private func requestSingleLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
        }
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN")) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let place = placemarks?.first
                continuation.resume(returning: Self.locationLabel(from: place))
            }
        }
    }

    private func fetchWeather(latitude: Double, longitude: Double) async throws -> OpenMeteoResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "precipitation"),
            URLQueryItem(name: "forecast_hours", value: "3"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    }

    private func handleLocationError(_ error: CLError) {
        snapshot = WeatherSnapshot(
            locationName: latestPlaceName ?? "定位不可用",
            temperature: 0,
            apparentTemperature: 0,
            humidity: 0,
            windSpeed: 0,
            conditionLabel: "需定位权限",
            icon: "location.slash.fill",
            updatedAt: "--:--",
            nextThreeHoursRainHint: "未来3小时内不会下雨"
        )

        switch error.code {
        case .denied, .network:
            break
        default:
            break
        }
    }

    private static func weatherInfo(for code: Int) -> (label: String, icon: String) {
        switch code {
        case 0: return ("晴朗", "sun.max.fill")
        case 1: return ("大部晴", "sun.max")
        case 2: return ("局部多云", "cloud.sun.fill")
        case 3: return ("阴天", "cloud.fill")
        case 45, 48: return ("有雾", "cloud.fog.fill")
        case 51, 53, 55, 61, 63, 80, 81: return ("降雨", "cloud.drizzle.fill")
        case 65, 82, 95, 96, 99: return ("强降雨", "cloud.bolt.rain.fill")
        case 71, 73, 75: return ("降雪", "cloud.snow.fill")
        default: return ("天气更新中", "cloud.fill")
        }
    }

    private static func nextThreeHoursRainHint(from weather: OpenMeteoResponse) -> String {
        let nextThreeHoursWillRain = weather.hourly.precipitation.prefix(3).contains { $0 > 0.05 }
        return nextThreeHoursWillRain ? "未来3小时内会下雨" : "未来3小时内不会下雨"
    }

    private static func locationLabel(from placemark: CLPlacemark?) -> String {
        guard let placemark else { return "当前位置" }

        let postalAddress = placemark.postalAddress

        // Prefer the most recognisable city + district pair across macOS versions.
        let cityCandidates = [
            placemark.locality,
            postalAddress?.city,
            placemark.subAdministrativeArea,
            placemark.administrativeArea
        ]
        let districtCandidates = [
            placemark.subLocality,
            postalAddress?.subLocality,
            postalAddress?.subAdministrativeArea,
            inferredDistrictName(from: placemark),
            placemark.name
        ]

        let city = cityCandidates
            .compactMap { normalizedCityName($0) }
            .first

        let district = districtCandidates
            .compactMap { normalizedDistrictName($0) }
            .first { candidate in
                candidate != city
            }

        let parts = [city, district]
            .compactMap { $0 }
            .reduce(into: [String]()) { partial, item in
                if !partial.contains(item) {
                    partial.append(item)
                }
            }

        if let city, let district {
            return "\(city) · \(district)"
        }

        return parts.isEmpty ? "当前位置" : parts.joined(separator: " · ")
    }

    private static func inferredDistrictName(from placemark: CLPlacemark) -> String? {
        let rawCandidates = [
            placemark.name,
            placemark.inlandWater,
            placemark.ocean
        ]

        let cityParts = [
            normalizedCityName(placemark.locality),
            normalizedCityName(placemark.subAdministrativeArea),
            normalizedCityName(placemark.administrativeArea)
        ].compactMap { $0 }

        for raw in rawCandidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) where !raw.isEmpty {
            var candidate = raw
            for cityPart in cityParts {
                candidate = candidate.replacingOccurrences(of: cityPart, with: "")
            }
            candidate = candidate
                .replacingOccurrences(of: "中国", with: "")
                .replacingOccurrences(of: "中华人民共和国", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let normalized = normalizedDistrictName(candidate) {
                return normalized
            }
        }

        return nil
    }

    private static func normalizedCityName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.contains("市") || value.contains("自治州") || value.contains("地区") || value.contains("盟") {
            return value
        }
        return value + "市"
    }

    private static func normalizedDistrictName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.contains("区") || value.contains("县") || value.contains("市") || value.contains("旗") {
            return value
        }

        return nil
    }
}

extension WeatherViewModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.authorizationContinuation?.resume()
                self.authorizationContinuation = nil
                if self.snapshot.locationName == WeatherSnapshot.placeholder.locationName {
                    self.refreshWeather()
                }
            case .denied, .restricted:
                self.authorizationContinuation?.resume(throwing: CLError(.denied))
                self.authorizationContinuation = nil
                self.handleLocationError(CLError(.denied))
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.latestLocation = location
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(throwing: error)
            self.locationContinuation = nil
        }
    }
}
