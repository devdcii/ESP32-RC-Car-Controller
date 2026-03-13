# ESP32 RC Car Controller
### IoT-Based Remote Control Car System

> A Flutter mobile app that controls an ESP32-powered RC car over a direct WiFi connection — featuring a virtual joystick, 3 speed modes, real-time battery monitoring, and 4-direction motor control via L298N motor driver.

---

## Overview

ESP32 RC Car Controller is a landscape-mode iOS-style Flutter app that connects directly to an ESP32 Access Point to control a 2-motor RC car. The app features a virtual joystick for intuitive control, three speed modes (Neutral, Low, High), and a live dashboard showing battery level, speed, and current direction. The ESP32 uses an L298N dual motor driver to independently control left and right motors with PWM speed control.

---

## Features

- **Virtual Joystick** — smooth drag-based control with 4-direction movement (Forward, Backward, Left, Right)
- **3 Speed Modes** — Neutral (30%), Low (60%), High (100%) PWM control
- **Live Status Dashboard** — real-time battery level, speed percentage, and direction indicator
- **Connection Timeout Safety** — motors auto-stop after 5 seconds of no command
- **PWM Speed Control** — independent speed control for left and right motors via ENA/ENB pins
- **Landscape Mode** — forced landscape orientation for better controller experience
- **Hive Logging** — local storage of control history (direction + speed + timestamp)
- **Web Control Panel** — browser-accessible basic control at `http://192.168.4.1`

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile App | Flutter 3.x (Dart) |
| UI Style | Cupertino (iOS-style) |
| Local Storage | Hive / hive_flutter |
| HTTP Client | http package |
| Microcontroller | ESP32 |
| Firmware | Arduino (C++) |
| Motor Driver | L298N Dual H-Bridge |
| Communication | WiFi (ESP32 Access Point) |
| Data Format | JSON / REST |

---

## Project Structure

```
rc-car-controller/
├── app/                              # Flutter Mobile App
│   ├── lib/
│   │   └── main.dart                 # Full app (ESP32Service, joystick, UI)
│   └── pubspec.yaml
│
└── firmware/                         # ESP32 Arduino Code
    └── rc_car/
        └── rc_car.ino                # Main firmware file
```

---

## Hardware

### Components

| Component | Model | Purpose |
|---|---|---|
| Microcontroller | ESP32 Dev Module | WiFi Access Point + motor controller |
| Motor Driver | L298N Dual H-Bridge | Controls 2 DC motors |
| Left Motor | DC Motor | Left wheel drive |
| Right Motor | DC Motor | Right wheel drive |
| Power Supply | 12V Battery | Powers motors + ESP32 |

### Wiring — ESP32 to L298N

| L298N Pin | ESP32 Pin | GPIO | Purpose |
|---|---|---|---|
| IN1 | D13 | GPIO 13 | Left Motor direction A |
| IN2 | D14 | GPIO 14 | Left Motor direction B |
| IN3 | D26 | GPIO 26 | Right Motor direction A |
| IN4 | D27 | GPIO 27 | Right Motor direction B |
| ENA | D5 | GPIO 5 | Left Motor PWM speed |
| ENB | D18 | GPIO 18 | Right Motor PWM speed |
| GND | GND | — | Common ground |
| 12V | External Battery | — | Motor power supply |

> **Note:** The L298N 5V output can power the ESP32 if jumper is enabled (only when using 7V+ motor supply). Add a 100uF capacitor across the motor power terminals to reduce noise.

### Motor Direction Logic

| Direction | Left Motor | Right Motor |
|---|---|---|
| Forward | Forward (+) | Forward (+) |
| Backward | Backward (-) | Backward (-) |
| Turn Left | Backward (-) | Forward (+) |
| Turn Right | Forward (+) | Backward (-) |

### ESP32 WiFi Setup

The ESP32 creates its own Access Point — no router required.

| Setting | Value |
|---|---|
| SSID | DevRC Controller |
| Password | 12345678 |
| ESP32 IP | 192.168.4.1 |
| Timeout | 5 seconds (auto-stop) |

### ESP32 HTTP API

Base URL: `http://192.168.4.1`

| Endpoint | Method | Description |
|---|---|---|
| `/` | GET | Web control panel |
| `/connect` | POST | Register app connection |
| `/disconnect` | POST | Disconnect and stop motors |
| `/status` | GET | Battery, speed, direction, clients |
| `/control` | POST | Send joystick direction + speed |
| `/forward` | GET | Move forward at 60% speed |
| `/backward` | GET | Move backward at 60% speed |
| `/left` | GET | Turn left at 60% speed |
| `/right` | GET | Turn right at 60% speed |
| `/stop` | GET | Stop all motors |

### Control Payload

```json
POST /control
{
  "x": 50.0,
  "y": -50.0,
  "speed": 0.6,
  "direction": "FORWARD"
}
```

### Arduino IDE Setup

1. Install **Arduino IDE** and add ESP32 board support
   - Board Manager URL: `https://dl.espressif.com/dl/package_esp32_index.json`
2. Install required libraries via Library Manager:
   - `ArduinoJson` by Benoit Blanchon
3. Open `firmware/rc_car/rc_car.ino`
4. Update credentials if needed:
```cpp
const char* ssid = "DevRC Controller";
const char* password = "12345678";
```
5. Update motor pins if your wiring differs:
```cpp
#define IN1 13   // Left Motor direction A
#define IN2 14   // Left Motor direction B
#define IN3 26   // Right Motor direction A
#define IN4 27   // Right Motor direction B
#define ENA_PIN 5   // Left Motor PWM
#define ENB_PIN 18  // Right Motor PWM
```
6. Select board: **ESP32 Dev Module**
7. Upload to ESP32
8. Open Serial Monitor at **115200 baud** to verify startup and motor commands

---

## Mobile App Setup

### Prerequisites

- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android Studio or VS Code with Flutter extensions

### Installation

```bash
cd app
flutter pub get
flutter run
```

### Connecting to the RC Car

1. Power on the ESP32 and RC car
2. On your phone, connect to WiFi: **DevRC Controller** (password: `12345678`)
3. Open the app — tap **Connect** button
4. Use the joystick to control the car
5. Select speed mode: Neutral / Low / High

---

## App Layout (Landscape Mode)

| Section | Description |
|---|---|
| Header | App title, connection status, Connect/Disconnect button |
| Status Cards | Battery %, current speed %, current direction |
| Joystick | Virtual drag joystick — controls FORWARD / BACKWARD / LEFT / RIGHT |
| Speed Modes | 3 circular buttons — Neutral (30%), Low (60%), High (100%) |

---

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  http: ^1.5.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

---

## Roadmap

- [ ] Turbo boost button for temporary max speed
- [ ] Steering sensitivity adjustment slider
- [ ] Real battery voltage sensor integration
- [ ] Headlight / horn control
- [ ] Control history replay
- [ ] Gyroscope-based tilt steering option
