const collapsedTemp = document.querySelector('#collapsed-temp');
const heroTemp = document.querySelector('#hero-temp');
const apparentTemp = document.querySelector('#apparent-temp');
const windSpeed = document.querySelector('#wind-speed');
const humidity = document.querySelector('#humidity');
const updatedAt = document.querySelector('#updated-at');
const locationName = document.querySelector('#location-name');
const weatherSummary = document.querySelector('#weather-summary');
const weatherBadge = document.querySelector('#weather-badge');
const heroIcon = document.querySelector('#hero-icon');
const statusText = document.querySelector('#status-text');
const refreshBtn = document.querySelector('#refresh-btn');

const WEATHER_MAP = {
  0: { label: '晴朗', icon: '☀' },
  1: { label: '大部晴', icon: '🌤' },
  2: { label: '局部多云', icon: '⛅' },
  3: { label: '阴天', icon: '☁' },
  45: { label: '有雾', icon: '🌫' },
  48: { label: '冻雾', icon: '🌫' },
  51: { label: '毛毛雨', icon: '🌦' },
  53: { label: '小雨', icon: '🌦' },
  55: { label: '中雨', icon: '🌧' },
  61: { label: '阵雨', icon: '🌧' },
  63: { label: '降雨', icon: '🌧' },
  65: { label: '大雨', icon: '⛈' },
  71: { label: '小雪', icon: '🌨' },
  73: { label: '降雪', icon: '🌨' },
  75: { label: '暴雪', icon: '❄' },
  80: { label: '短时阵雨', icon: '🌦' },
  81: { label: '阵雨增强', icon: '🌧' },
  82: { label: '暴雨阵雨', icon: '⛈' },
  95: { label: '雷暴', icon: '⛈' },
  96: { label: '雷暴冰雹', icon: '⛈' },
  99: { label: '强雷暴', icon: '⛈' },
};

let refreshTimer = null;
let latestPosition = null;

function weatherInfo(code) {
  return WEATHER_MAP[code] || { label: '天气更新中', icon: '☁' };
}

function setStatus(text) {
  statusText.textContent = text;
}

function formatTime(date = new Date()) {
  return new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`请求失败: ${response.status}`);
  }
  return response.json();
}

async function reverseGeocode(latitude, longitude) {
  const url = new URL('https://geocoding-api.open-meteo.com/v1/reverse');
  url.searchParams.set('latitude', latitude);
  url.searchParams.set('longitude', longitude);
  url.searchParams.set('language', 'zh');
  url.searchParams.set('format', 'json');

  const data = await fetchJson(url.toString());
  const result = data.results?.[0];
  if (!result) {
    return '当前位置';
  }

  const parts = [result.name, result.admin1, result.country].filter(Boolean);
  return [...new Set(parts)].slice(0, 2).join(' · ');
}

async function loadWeather(latitude, longitude) {
  const url = new URL('https://api.open-meteo.com/v1/forecast');
  url.searchParams.set('latitude', latitude);
  url.searchParams.set('longitude', longitude);
  url.searchParams.set('current', 'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m');
  url.searchParams.set('timezone', 'auto');

  const [weatherData, placeName] = await Promise.all([
    fetchJson(url.toString()),
    reverseGeocode(latitude, longitude).catch(() => '当前位置'),
  ]);

  const current = weatherData.current;
  if (!current) {
    throw new Error('未返回当前天气');
  }

  const info = weatherInfo(current.weather_code);
  collapsedTemp.textContent = `${Math.round(current.temperature_2m)}°`;
  heroTemp.textContent = `${Math.round(current.temperature_2m)}`;
  apparentTemp.textContent = `${Math.round(current.apparent_temperature)}°C`;
  windSpeed.textContent = `${Math.round(current.wind_speed_10m)} km/h`;
  humidity.textContent = `${Math.round(current.relative_humidity_2m)}%`;
  updatedAt.textContent = formatTime();
  locationName.textContent = placeName;
  weatherSummary.textContent = `${info.label}，适合快速查看当前天气动态。`;
  weatherBadge.textContent = info.label;
  heroIcon.textContent = info.icon;
  setStatus('活动持续运行中，每 10 分钟自动更新一次。');
}

async function refreshWeather() {
  try {
    refreshBtn.disabled = true;
    refreshBtn.textContent = '更新中...';
    setStatus('正在同步你所在位置的天气...');

    const position = latestPosition || (await requestLocation());
    latestPosition = position;
    const { latitude, longitude } = position.coords;
    await loadWeather(latitude, longitude);
  } catch (error) {
    console.error(error);
    collapsedTemp.textContent = '--°';
    heroTemp.textContent = '--';
    weatherSummary.textContent = '无法获取天气，请检查定位权限或网络连接。';
    weatherBadge.textContent = '未连接';
    heroIcon.textContent = '􀇥';
    locationName.textContent = '天气不可用';
    setStatus('获取失败：请允许定位权限后重试。');
  } finally {
    refreshBtn.disabled = false;
    refreshBtn.textContent = '刷新天气';
  }
}

function requestLocation() {
  if (!navigator.geolocation) {
    throw new Error('当前浏览器不支持地理定位');
  }

  return new Promise((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: true,
      timeout: 12000,
      maximumAge: 300000,
    });
  });
}

function startAutoRefresh() {
  if (refreshTimer) {
    window.clearInterval(refreshTimer);
  }

  refreshTimer = window.setInterval(() => {
    refreshWeather();
  }, 10 * 60 * 1000);
}

refreshBtn.addEventListener('click', refreshWeather);

refreshWeather();
startAutoRefresh();
