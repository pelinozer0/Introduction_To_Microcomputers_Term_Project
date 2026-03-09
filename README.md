🏠 Home Automation System

PIC16F877A-Based Embedded System with PC User Interface

📌 Project Overview

This project implements a microcontroller-based home automation system consisting of two independent hardware boards and a PC-side application. The system allows users to monitor environmental data and control home devices through a graphical user interface (GUI) using UART communication.

The project is developed as part of the Introduction to Microcomputers course and focuses on embedded system design, serial communication, and PC–microcontroller interaction.

## 💡 Personal Contribution
This project was developed as a cross-disciplinary team effort between Computer Engineering and Electrical-Electronics Engineering students.

My primary responsibilities and technical contributions focused on the software and communication layers:
* **User Interface (UI) Development:** Designed and coded the Python-based graphical user interface (GUI) from scratch, ensuring smooth user interaction and real-time sensor data visualization.
* **UART Communication Logic:** Implemented the PC-side API layer to establish reliable, bidirectional serial communication between the desktop interface and the PIC16F877A microcontrollers.

🧩 System Architecture

The system is composed of three main layers:

PC-Side Application (User Interface)

Communication Layer (UART)

Microcontroller Boards (PIC16F877A)

The PC application communicates with the microcontroller boards through UART using a modular API structure. This separation ensures clean design, modularity, and easier debugging.

🖥️ PC-Side User Interface

The graphical user interface is implemented in Python and serves as the main interaction point between the user and the system.

Features:

Main menu for system selection

Air Conditioner Control Screen (Board #1)

Curtain Control Screen (Board #2)

Real-time display of sensor values

User input validation and feedback messages

Thread-based background updates to prevent UI freezing

The UI does not communicate directly with the hardware. Instead, all serial communication is handled through an API layer that abstracts low-level UART operations.

🔌 UART Communication

UART is used as the primary communication protocol between the PC application and the microcontroller boards.

UART Configuration:

Baud Rate: 9600

Data Bits: 8

Parity: None

Stop Bits: 1

Communication Type: Bidirectional

Commands and sensor data are exchanged using predefined byte-level protocols to ensure reliable data transfer.

🧠 Board #2 – Curtain Control System

Board #2 is responsible for controlling the curtain mechanism and collecting environmental data.

Hardware Components:

PIC16F877A Microcontroller

Step Motor (Curtain movement)

LDR Sensor (Light intensity measurement)

UART module for serial communication

Functionality:

Receives curtain position commands from the PC

Controls step motor movement based on received values

Measures ambient light intensity using LDR

Sends curtain status and sensor data back to the PC

All UART parsing, command handling, and peripheral control logic are implemented on the microcontroller side.

🧪 Real-Time Data Update Mechanism

The PC application continuously updates system data using a background thread that runs approximately every 500 ms. Short delays (20–50 ms) are applied between UART commands to ensure stable communication.

This approach allows:

Smooth user interface interaction

Near real-time monitoring of system status

Reliable synchronization between hardware and software

⚠️ Error Handling and Input Validation

To ensure system safety and stability:

Temperature values are limited to 10–50 °C

Curtain position values are limited to 0–100%

Non-numeric inputs are rejected

Users receive clear success and error messages

These constraints prevent invalid commands from reaching the hardware.
