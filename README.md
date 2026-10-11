# IoT-Based Chopped Grass Feed Automation System

*An IoT-based automated chopped grass feeding system that combines a Double Stage Conveyor, ESP32, sensor-based feed profiling, time-based dosing control, Firebase Realtime Database, and a Flutter mobile application.*

## 📌 The Problem

Manual livestock feeding in smallholder farms can lead to inconsistent feed portions, unnecessary feed waste, and inefficient time management. Feed is often distributed based on estimation rather than a measurable dosing standard, making the actual amount difficult to control consistently.

Chopped grass also has variable physical characteristics. Differences between stem and leaf portions, together with higher cohesion in wet feed, can affect the flow rate and consistency of the delivered feed.

The system was developed to provide a low-cost automated solution that improves dosing consistency while enabling remote monitoring and control through an IoT architecture.

## 💡 The Solution

This project implements an **IoT-based automatic feeding system for chopped grass** using an **ESP32 DevKit V1** as the main controller.

The physical feeding mechanism uses a **Double Stage Conveyor with cleats**, driven by two high-torque DC gearbox motors. The first conveyor is responsible for dosing, while the second conveyor distributes the feed toward the feeding area.

The system integrates three primary sensing functions:

* **HC-SR04 Ultrasonic Sensor** - monitors the remaining feed stock inside the hopper.
* **Capacitive Moisture Sensor** - classifies feed conditions as wet or dry for actuator profiling.
* **PIR Sensor** - detects livestock activity around the feeding area after feed delivery.

The ESP32 processes sensor data, synchronizes time through **Network Time Protocol (NTP)**, executes scheduled or on-demand feeding commands, and communicates with **Firebase Realtime Database (RTDB)**.

A **Flutter mobile application** provides remote access to the feeding system through Firebase. The application includes dashboard monitoring, instant feeding, custom scheduling, sensor requests, feeding history, and operational settings.

### ⚙️ System Workflow

```text
Sensors & User Commands
        │
        ▼
   ESP32 DevKit V1
        │
        ├── NTP Time Synchronization
        ├── Feed Condition Classification
        ├── Stock Monitoring
        ├── Dosing Logic
        └── Safety / Fail-Safe Logic
        │
        ▼
 Double Stage Conveyor
   ├── Motor 1 → Dosing
   └── Motor 2 → Distribution
        │
        ▼
   Feeding Area
        │
        ├── PIR Monitoring
        │
        ▼
Firebase Realtime Database
        │
        ▼
 Flutter Mobile Application
```

## 🚀 Key Features

### Automated Feeding

The system executes feeding based on configured schedules and target doses without requiring manual operation at every feeding session.

### Time-Based Dosing with PWM

Motor speed is controlled using **Pulse Width Modulation (PWM)**. The dosing profile is calibrated for target weights between **500 g and 1000 g**.

The system adjusts the dosing motor profile according to feed condition:

* **Dry feed** → higher PWM profile
* **Wet feed** → lower PWM profile

This approach keeps the operating duration controlled while adjusting actuator power according to material characteristics.

### Smart Dosing

The mobile application provides a **Smart Dosing** function that calculates daily feed requirements from livestock body weight.

The system uses a feed requirement of **10% of body weight** and distributes the calculated amount across active daily feeding sessions.

Users can also define the target amount per feeding session manually.

### Feed Stock Monitoring

The HC-SR04 sensor monitors the feed level inside the hopper.

A fail-safe condition prevents motor operation when the measured stock distance reaches the critical threshold of **32 cm or more**, indicating insufficient feed stock.

### Feed Activity Monitoring

The PIR sensor monitors livestock activity around the feeding area after feeding execution.

To reduce unnecessary database traffic, PIR monitoring is limited to a defined monitoring window after feed delivery, with a **5-minute reporting cooldown**.

### On-Demand Sensor Monitoring

Sensor readings are not continuously pushed to the application.

The mobile application can request an update through the **"Check Stock and Moisture"** function, after which the ESP32 reads the sensors and sends the latest values to Firebase.

### Remote Control & Scheduling

The Flutter application supports:

* Instant feeding
* Custom feeding schedules
* Daily feeding session configuration
* Feed stock monitoring
* Feed moisture monitoring
* Feeding history
* Operational settings

## 🧠 System Architecture

The system uses a centralized IoT architecture composed of three major layers.

### Hardware Layer

The ESP32 acts as the central controller and interfaces with the sensors, motor drivers, and DC motors.

### Cloud Layer

**Firebase Realtime Database** provides real-time data exchange between the ESP32 and Flutter application.

The RTDB is organized into four major data areas:

```text
Configuration
Commands
Monitoring
History
```

Configuration stores operational parameters, schedules, modes, and target doses.

Commands are used for instant/custom feeding and on-demand sensor requests.

Monitoring contains current feed-stock, moisture, and PIR activity information.

History stores previous feeding execution records for monitoring and evaluation.

### Application Layer

The Flutter mobile application provides the user interface for monitoring, configuration, remote feeding control, and historical data.

Authentication and **Rule-Based Access Control (RBAC)** are used to restrict access to critical configuration and actuator control operations.

## 🛠️ Hardware

| Component         | Specification                             | Function                                     |
| ----------------- | ----------------------------------------- | -------------------------------------------- |
| Microcontroller   | ESP32 DevKit V1                           | Main system controller                       |
| Motor 1           | JGY-370 DC Gearbox, 66–100 RPM, 12V       | Feed dosing conveyor                         |
| Motor 2           | JGY-370 DC Gearbox, 66–100 RPM, 12V       | Feed distribution conveyor                   |
| Motor Driver      | BTS7960                                   | Motor direction and PWM speed control        |
| Mechanical System | Double Stage Conveyor with Cleats         | Feed transport and positive displacement     |
| Stock Sensor      | HC-SR04                                   | Hopper stock monitoring                      |
| Activity Sensor   | PIR                                       | Livestock activity detection                 |
| Moisture Sensor   | Capacitive Soil Moisture Sensor v1.2/v2.0 | Wet/dry feed classification                  |
| Power Supply      | 12V 15A                                   | Main power source                            |
| Buck Converter    | LM2596                                    | Voltage step-down for controller and sensors |

The hardware specification and pin mapping are documented in the research report.

## 💻 Software Stack

| Technology                 | Purpose                      |
| -------------------------- | ---------------------------- |
| C++                        | ESP32 firmware               |
| Arduino IDE                | Firmware development         |
| ESP32                      | Embedded controller          |
| Flutter                    | Mobile application           |
| Dart                       | Flutter application language |
| Firebase Realtime Database | Cloud data synchronization   |
| Firebase Authentication    | User authentication          |
| NTP                        | Time synchronization         |
| PWM                        | Motor speed control          |
| JSON / RTDB                | Cloud data structure         |
| Rule-Based Access Control  | Database authorization       |

The ESP32 firmware is implemented using C++ in Arduino IDE, while the mobile interface is developed with Flutter and connected to Firebase RTDB.

## 📊 Testing & Results

The prototype was evaluated through functional black-box testing, sensor validation, and feeding-dose accuracy experiments.

### Feeding Accuracy

| Condition | Target | Average Error | Standard Deviation |
| --------- | -----: | ------------: | -----------------: |
| Dry Feed  |  500 g |          6.0% |            35.34 g |
| Dry Feed  | 1000 g |      **5.4%** |            47.56 g |
| Wet Feed  |  500 g |         12.0% |            77.06 g |
| Wet Feed  | 1000 g |         10.2% |            88.67 g |

For the 1000 g dry-feed scenario, the IoT prototype achieved an average error of **5.4%**, compared with **21.0%** for the manual baseline.

This corresponds to:

```text
Manual Measurement
Error    : 21.0%
Accuracy : 79.0%

IoT Prototype
Error    : 5.4%
Accuracy : 94.6%
```

The higher error observed in wet feed was associated with stronger material cohesion and differences in the stem-to-leaf composition of the chopped grass.

### Sensor Classification

The capacitive moisture sensor achieved **100% classification accuracy** for distinguishing wet and dry feed conditions during validation.

### IoT Functional Reliability

Black-box testing achieved a **100% Success Rate** across the main functional test scenarios.

| Test Scenario                     | Trials | Success Rate |
| --------------------------------- | -----: | -----------: |
| NTP Synchronization & Scheduling  |     15 |         100% |
| Instant & Custom Feeding Commands |     10 |         100% |
| On-Demand Sensor Updates          |      3 |         100% |
| Fail-Safe & Hybrid Logic          |     10 |         100% |
| Access Security                   |      3 |         100% |
| **Total**                         | **41** |     **100%** |

The system successfully executed scheduled feeding, on-demand commands, sensor updates, fail-safe logic, and access-control validation in the tested scenarios.

## 🔐 Safety & Security

The system applies multiple protection mechanisms.

### Fail-Safe Feed Protection

When the ultrasonic sensor detects a critical stock distance of **32 cm or more**, motor execution is cancelled to prevent inaccurate or empty feeding cycles.

### Authentication

Firebase Authentication is used to prevent unauthorized application access.

### Rule-Based Access Control

Critical nodes such as schedules and actuator-related parameters are restricted to authorized users, while device access is limited according to its intended role.

### Network Dependency

The automatic scheduling mechanism relies on **NTP synchronization through an internet connection**. Because the low-cost prototype does not include a physical RTC module, loss of connectivity can prevent scheduled execution.

## 📂 Repository Structure

```text
iot-chopped-grass-feeding-system/
├── README.md
│
├── docs/
│   ├── Level 0 DFD (Context Diagram).png
│   ├── Level 1 DFD for the Feed Automation System.png
│   ├── Main System Logic Flowchart.png
│   ├── Mobile App Interface.png
│   └── Transformation of a Conceptual Model into an RTDB Structure.png
│
├── hardware/
│   ├── images/
│   │   ├── Mechanical Design of a Double-Stage Conveyor.png
│   │   └── System Wiring Diagram.png
│   │
│   └── source_code_esp32/
│       └── Source_Code_ESP32/
│           └── Source_Code_ESP32.ino
│
└── software/
    ├── flutter/
    │    ├── database.rules.json
    │    ├── firebase.json
    │    ├── documentation.md
    │    ├── pubspec.yaml
    │    ├── pubspec.lock
    │    └── lib/
    │        ├── app/
    │        ├── core/
    │        ├── features/
    │        ├── shared/
    │        └── main.dart
    └── RTDB Structure/
         └── sistem-otomasi-pakan-ternak-default-rtdb-export.json
```

The repository separates system documentation, ESP32 hardware implementation, RTDB structure, and the Flutter application.

## 📸 Project Gallery

### System Architecture

<img src="docs/Level 0 DFD (Context Diagram).png" width="450">

<img src="docs/Level 1 DFD for the Feed Automation System.png" width="450">

<img src="docs/Main System Logic Flowchart.png" width="450">

### Mechanical & Hardware

<img src="hardware/images/Mechanical Design of a Double-Stage Conveyor.png" width="450">

<img src="hardware/images/System Wiring Diagram.png" width="450">

### Mobile Application

<img src="docs/Mobile App Interface.png" width="450">

### Firebase Realtime Database

<img src="docs/Transformation of a Conceptual Model into an RTDB Structure.png" width="450">

## 📈 Project Impact

The prototype demonstrates that a low-cost IoT architecture can improve feed dosing consistency while reducing dependence on manual feeding operations.

Key outcomes include:

* **5.4% average error** for 1000 g dry-feed dosing.
* **94.6% accuracy** for the 1000 g dry-feed prototype scenario.
* **21.0% manual baseline error** for comparison.
* **100% moisture-condition classification accuracy** during validation.
* **100% IoT functional Success Rate** across 41 primary test trials.
* Successful implementation of automated scheduling, on-demand monitoring, fail-safe control, and access security.
* Feeding operation remained functional without observed mechanical clogging during the reported testing scenarios.

## 📈 (Business Value)

By shifting from manual estimation to precision automation, the system provides:

* **Cost Efficiency:** Significantly reduces feed waste through high-precision dosing compared to manual methods.
* **Labor Optimization:** Frees up farmers' time by automating daily feeding schedules.
* **Operational Reliability:** Ensures consistent operation without mechanical clogging, supported by a smart fail-safe mechanism to protect hardware longevity.

## ⚠️ Limitations & Future Improvements

The current prototype still has several development limitations:

* Automatic scheduling depends on internet connectivity and NTP synchronization because no physical RTC is installed.
* Accuracy validation is limited to the calibrated **500–1000 g** target range.
* Wet feed produces greater variability because of material cohesion and non-uniform stem/leaf composition.
* Further mechanical improvements are needed to increase hopper capacity and reduce the possibility of motor stall.

Future development can include:

* Physical RTC integration for offline scheduling.
* Dynamic Wi-Fi provisioning.
* Custom time-zone management.
* More flexible scheduling and dosing configuration.
* Increased hopper capacity and mechanical robustness.
* Further development toward zero-code configuration and improved deployment scalability.

## 🎓 Research Information

**Research Title:**
*Rancang Bangun Sistem Otomasi Pakan Rumput Cacah Menggunakan Mekanisme Double Stage Conveyor Dengan Kontrol Dosis Berbasis Waktu Dan IoT*

**Author:** Sendy Tegar Mahendra
**Study Program:** Computer Engineering
**Institution:** Universitas Muhammadiyah Karanganyar
**Year:** 2026

## 📄 Research Scope

This repository contains the main implementation and supporting documentation for an undergraduate research project focused on:

* Automated livestock feeding
* Precision feed dosing
* IoT-based monitoring and control
* Double Stage Conveyor mechanisms
* ESP32 embedded systems
* Firebase cloud integration
* Flutter mobile application development
* Sensor-based feed classification
* Automated scheduling and fail-safe control
