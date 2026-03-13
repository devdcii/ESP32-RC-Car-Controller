#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>

// Wi-Fi credentials for Access Point mode
const char* ssid = "DevRC Controller";
const char* password = "12345678";

// Static IP configuration
IPAddress local_ip(192, 168, 4, 1);
IPAddress gateway(192, 168, 4, 1);
IPAddress subnet(255, 255, 255, 0);

// Motor driver pins (L298N)
#define IN1 13 // Motor A, Input 1 (Left Motor)
#define IN2 14 // Motor A, Input 2 (Left Motor)
#define IN3 26 // Motor B, Input 1 (Right Motor)
#define IN4 27 // Motor B, Input 2 (Right Motor)

// ENA and ENB pins for speed control (PWM)
#define ENA_PIN 5  // Enable pin for Motor A (Left Motor) 
#define ENB_PIN 18 // Enable pin for Motor B (Right Motor)

// Status variables
float batteryVoltage = 12.0; // Simulated battery voltage
bool isConnected = false;
unsigned long lastCommandTime = 0;
const unsigned long CONNECTION_TIMEOUT = 5000; // 5 seconds

// Current motor states
int currentLeftSpeed = 0;
int currentRightSpeed = 0;
String currentDirection = "STOP";

WebServer server(80);

// === Motor control functions ===
void setMotorSpeed(int leftSpeed, int rightSpeed) {
  // Constrain speeds to valid PWM range (0-255)
  leftSpeed = constrain(leftSpeed, -255, 255);
  rightSpeed = constrain(rightSpeed, -255, 255);
  
  // Set left motor (Motor A)
  if (leftSpeed > 0) {
    digitalWrite(IN1, HIGH);
    digitalWrite(IN2, LOW);
    analogWrite(ENA_PIN, abs(leftSpeed));
  } else if (leftSpeed < 0) {
    digitalWrite(IN1, LOW);
    digitalWrite(IN2, HIGH);
    analogWrite(ENA_PIN, abs(leftSpeed));
  } else {
    digitalWrite(IN1, LOW);
    digitalWrite(IN2, LOW);
    analogWrite(ENA_PIN, 0);
  }
  
  // Set right motor (Motor B)
  if (rightSpeed > 0) {
    digitalWrite(IN3, HIGH);
    digitalWrite(IN4, LOW);
    analogWrite(ENB_PIN, abs(rightSpeed));
  } else if (rightSpeed < 0) {
    digitalWrite(IN3, LOW);
    digitalWrite(IN4, HIGH);
    analogWrite(ENB_PIN, abs(rightSpeed));
  } else {
    digitalWrite(IN3, LOW);
    digitalWrite(IN4, LOW);
    analogWrite(ENB_PIN, 0);
  }
  
  currentLeftSpeed = leftSpeed;
  currentRightSpeed = rightSpeed;
}

void stopMotors() {
  setMotorSpeed(0, 0);
  currentDirection = "STOP";
  Serial.println("Motors stopped");
}

// FIXED: Handle basic 4-direction movement with corrected left/right logic
void handleBasicMovement(String direction, float speedMultiplier) {
  int basePWM = (int)(255 * speedMultiplier); // Convert speed multiplier to PWM value
  
  currentDirection = direction;
  
  if (direction == "FORWARD") {
    // Both motors forward
    setMotorSpeed(basePWM, basePWM);
    Serial.printf("Moving FORWARD - Speed: %d\n", basePWM);
  } 
  else if (direction == "BACKWARD") {
    // Both motors backward
    setMotorSpeed(-basePWM, -basePWM);
    Serial.printf("Moving BACKWARD - Speed: %d\n", basePWM);
  } 
  else if (direction == "LEFT") {
    // FIXED: Turn left - right motor forward, left motor backward
    // This creates a left turn by having the right side push forward
    // while the left side pulls backward
    setMotorSpeed(-basePWM, basePWM);
    Serial.printf("Turning LEFT - Speed: %d\n", basePWM);
  } 
  else if (direction == "RIGHT") {
    // FIXED: Turn right - left motor forward, right motor backward  
    // This creates a right turn by having the left side push forward
    // while the right side pulls backward
    setMotorSpeed(basePWM, -basePWM);
    Serial.printf("Turning RIGHT - Speed: %d\n", basePWM);
  } 
  else {
    // STOP or any other command
    stopMotors();
  }
}

// === HTTP Route Handlers ===
void handleControl() {
  if (server.method() != HTTP_POST) {
    server.send(405, "application/json", "{\"error\":\"Method not allowed\"}");
    return;
  }
  
  String body = server.arg("plain");
  DynamicJsonDocument doc(512);
  DeserializationError error = deserializeJson(doc, body);
  
  if (error) {
    server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
    return;
  }
  
  // Extract values
  float x = doc["x"] | 0.0;
  float y = doc["y"] | 0.0;
  float speedMultiplier = doc["speed"] | 0.6;
  String direction = doc["direction"] | "STOP";
  
  // Update connection status
  isConnected = true;
  lastCommandTime = millis();
  
  // Handle basic movement based on direction
  handleBasicMovement(direction, speedMultiplier);
  
  // Send response
  DynamicJsonDocument response(256);
  response["status"] = "success";
  response["direction"] = currentDirection;
  response["leftSpeed"] = abs(currentLeftSpeed);
  response["rightSpeed"] = abs(currentRightSpeed);
  response["speedMultiplier"] = speedMultiplier;
  
  String responseString;
  serializeJson(response, responseString);
  server.send(200, "application/json", responseString);
}

void handleStatus() {
  // Simulate battery drain (very simple simulation)
  if (isConnected && (abs(currentLeftSpeed) > 0 || abs(currentRightSpeed) > 0)) {
    batteryVoltage -= 0.01; // Drain battery when moving
    if (batteryVoltage < 10.0) batteryVoltage = 10.0; // Minimum voltage
  }
  
  // Calculate battery percentage (12V = 100%, 10V = 0%)
  float batteryPercent = ((batteryVoltage - 10.0) / 2.0) * 100.0;
  batteryPercent = constrain(batteryPercent, 0, 100);
  
  DynamicJsonDocument response(512);
  response["connected"] = isConnected;
  response["battery"] = (int)batteryPercent;
  response["direction"] = currentDirection;
  response["leftSpeed"] = abs(currentLeftSpeed);
  response["rightSpeed"] = abs(currentRightSpeed);
  response["totalSpeed"] = (abs(currentLeftSpeed) + abs(currentRightSpeed)) / 2;
  response["voltage"] = batteryVoltage;
  response["ssid"] = ssid;
  response["ip"] = WiFi.softAPIP().toString();
  response["connectedClients"] = WiFi.softAPgetStationNum();
  
  String responseString;
  serializeJson(response, responseString);
  server.send(200, "application/json", responseString);
}

void handleConnect() {
  isConnected = true;
  lastCommandTime = millis();
  
  DynamicJsonDocument response(256);
  response["status"] = "connected";
  response["message"] = "Successfully connected to RC Car";
  response["ip"] = WiFi.softAPIP().toString();
  
  String responseString;
  serializeJson(response, responseString);
  server.send(200, "application/json", responseString);
  
  Serial.println("Client connected via HTTP");
}

void handleDisconnect() {
  isConnected = false;
  stopMotors();
  
  DynamicJsonDocument response(256);
  response["status"] = "disconnected";
  response["message"] = "Disconnected from RC Car";
  
  String responseString;
  serializeJson(response, responseString);
  server.send(200, "application/json", responseString);
  
  Serial.println("Client disconnected");
}

void setupRoutes() {
  // Enable CORS for all routes
  server.enableCORS(true);
  
  // Main control endpoint
  server.on("/control", HTTP_POST, handleControl);
  server.on("/control", HTTP_OPTIONS, []() { server.send(200); });
  
  // Status endpoint
  server.on("/status", HTTP_GET, handleStatus);
  
  // Connection management
  server.on("/connect", HTTP_POST, handleConnect);
  server.on("/disconnect", HTTP_POST, handleDisconnect);
  
  // Basic movement endpoints for direct control
  server.on("/forward", []() {
    handleBasicMovement("FORWARD", 0.6);
    server.send(200, "text/plain", "Moving forward");
  });
  
  server.on("/backward", []() {
    handleBasicMovement("BACKWARD", 0.6);
    server.send(200, "text/plain", "Moving backward");
  });
  
  server.on("/left", []() {
    handleBasicMovement("LEFT", 0.6);
    server.send(200, "text/plain", "Turning left");
  });
  
  server.on("/right", []() {
    handleBasicMovement("RIGHT", 0.6);
    server.send(200, "text/plain", "Turning right");
  });
  
  server.on("/stop", []() {
    stopMotors();
    server.send(200, "text/plain", "Stopped");
  });
  
  // Root endpoint
  server.on("/", []() {
    server.send(200, "text/html", 
      "<h1>ESP32 RC Car Controller</h1>"
      "<p>Access Point: " + String(ssid) + "</p>"
      "<p>IP Address: " + WiFi.softAPIP().toString() + "</p>"
      "<p>Status: Ready for connections</p>"
      "<p>Supported Movements: FORWARD, BACKWARD, LEFT, RIGHT, STOP</p>"
      "<p><strong>Motor Control Fixed:</strong> Left/Right directions now work correctly!</p>"
    );
  });
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  // Set motor pins as output
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(IN3, OUTPUT);
  pinMode(IN4, OUTPUT);
  pinMode(ENA_PIN, OUTPUT);
  pinMode(ENB_PIN, OUTPUT);

  stopMotors(); // Initialize motors to stop

  // Configure static IP
  if (!WiFi.softAPConfig(local_ip, gateway, subnet)) {
    Serial.println("❌ Failed to configure static IP");
  }

  // Start Access Point
  if (WiFi.softAP(ssid, password)) {
    Serial.println("✅ ESP32 Access Point started successfully");
    Serial.print("📡 Network: ");
    Serial.println(ssid);
    Serial.print("🔑 Password: ");
    Serial.println(password);
    Serial.print("🌐 IP Address: ");
    Serial.println(WiFi.softAPIP());
    Serial.println("🚗 RC Car Controller Ready!");
    Serial.println("📍 Movement modes: FORWARD, BACKWARD, LEFT, RIGHT, STOP");
    Serial.println("🔧 FIXED: Left/Right motor control corrected!");
  } else {
    Serial.println("❌ Failed to start Access Point");
  }

  setupRoutes();
  server.begin();
  Serial.println("🌐 HTTP Server started on port 80");
  Serial.println("📱 Ready for Flutter app connection!");
}

void loop() {
  server.handleClient();
  
  // Check for connection timeout
  if (isConnected && (millis() - lastCommandTime > CONNECTION_TIMEOUT)) {
    Serial.println("⚠️ Connection timeout - stopping motors");
    isConnected = false;
    stopMotors();
  }
  
  delay(10); // Small delay for stability
}