import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';

// Car Control Data Model
@HiveType(typeId: 0)
class CarControlData extends HiveObject {
  @HiveField(0)
  String direction;

  @HiveField(1)
  double speed;

  @HiveField(2)
  DateTime timestamp;

  CarControlData(this.direction, this.speed, this.timestamp);
}

// Car Control Data Adapter
class CarControlDataAdapter extends TypeAdapter<CarControlData> {
  @override
  final int typeId = 0;

  @override
  CarControlData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CarControlData(
      fields[0] as String,
      fields[1] as double,
      fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, CarControlData obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.direction)
      ..writeByte(1)
      ..write(obj.speed)
      ..writeByte(2)
      ..write(obj.timestamp);
  }
}

// ESP32 API Service
class ESP32Service {
  static const String ESP32_IP = "192.168.4.1";
  static const String BASE_URL = "http://$ESP32_IP";

  static Future<bool> connect() async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/connect'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        print('✅ Connected to ESP32 RC Car');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Connection failed: $e');
      return false;
    }
  }

  static Future<bool> disconnect() async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/disconnect'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Disconnect failed: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> sendControl(double x, double y, double speedMultiplier, String direction) async {
    try {
      final controlData = {
        'x': x,
        'y': y,
        'speed': speedMultiplier,
        'direction': direction,
      };

      final response = await http.post(
        Uri.parse('$BASE_URL/control'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(controlData),
      ).timeout(Duration(seconds: 2));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('❌ Control command failed: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$BASE_URL/status'),
      ).timeout(Duration(seconds: 3));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('❌ Status request failed: $e');
      return null;
    }
  }
}

// Speed Mode Enum
enum SpeedMode { low, mid, high }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(CarControlDataAdapter());
  await Hive.openBox<CarControlData>('car_controls');

  // Force landscape orientation for a better RC controller experience
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(RCCarApp());
}

class RCCarApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'ESP32 RC Controller',
      theme: const CupertinoThemeData(
        primaryColor: CupertinoColors.activeBlue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Color(0xFF1A1A1A),
        barBackgroundColor: Color(0xFF1A1A1A),
        textTheme: CupertinoTextThemeData(
          primaryColor: CupertinoColors.white,
          textStyle: TextStyle(
            fontFamily: 'Inter',
            color: CupertinoColors.white,
          ),
        ),
      ),
      home: RCCarHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class RCCarHomePage extends StatefulWidget {
  @override
  _RCCarHomePageState createState() => _RCCarHomePageState();
}

class _RCCarHomePageState extends State<RCCarHomePage>
    with TickerProviderStateMixin {
  late AnimationController _connectionAnimationController;
  late AnimationController _speedAnimationController;
  late AnimationController _batteryAnimationController;

  late Animation<double> _connectionAnimation;
  late Animation<double> _speedAnimation;
  late Animation<Color?> _batteryColorAnimation;

  Box<CarControlData>? _carControlsBox;
  Timer? _statusTimer;
  Timer? _controlTimer;

  bool _isConnected = false;
  String _currentDirection = 'STOP';
  double _joystickX = 0.0;
  double _joystickY = 0.0;
  double _batteryLevel = 100.0;
  SpeedMode _selectedSpeedMode = SpeedMode.mid;
  String _connectionStatus = 'Disconnected';
  int _connectedClients = 0;

  Offset _joystickPosition = Offset.zero;
  bool _isDraggingJoystick = false;

  @override
  void initState() {
    super.initState();
    _initHive();
    _setupAnimations();
  }

  void _initHive() {
    _carControlsBox = Hive.box<CarControlData>('car_controls');
  }

  void _setupAnimations() {
    _connectionAnimationController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );

    _speedAnimationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );

    _batteryAnimationController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );

    _connectionAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _connectionAnimationController,
      curve: Curves.easeInOut,
    ));

    _speedAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _speedAnimationController,
      curve: Curves.elasticOut,
    ));

    _batteryColorAnimation = ColorTween(
      begin: CupertinoColors.systemGreen,
      end: CupertinoColors.systemRed,
    ).animate(CurvedAnimation(
      parent: _batteryAnimationController,
      curve: Curves.easeInOut,
    ));

    _connectionAnimationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _connectionAnimationController.dispose();
    _speedAnimationController.dispose();
    _batteryAnimationController.dispose();
    _statusTimer?.cancel();
    _controlTimer?.cancel();
    super.dispose();
  }

  void _toggleConnection() async {
    if (_isConnected) {
      // Disconnect
      final success = await ESP32Service.disconnect();
      setState(() {
        _isConnected = false;
        _connectionStatus = 'Disconnected';
      });
      _connectionAnimationController.repeat(reverse: true);
      _stopCar();
      _statusTimer?.cancel();
      _controlTimer?.cancel();

      if (success) {
        _showMessage('Disconnected from ESP32 RC Car');
      }
    } else {
      // Connect
      setState(() {
        _connectionStatus = 'Connecting...';
      });

      final success = await ESP32Service.connect();

      if (success) {
        setState(() {
          _isConnected = true;
          _connectionStatus = 'Connected';
        });
        _connectionAnimationController.stop();
        _connectionAnimationController.value = 1.0;
        _startStatusUpdates();
        _showMessage('Connected to ESP32 RC Car!');
      } else {
        setState(() {
          _connectionStatus = 'Connection Failed';
        });
        _showMessage('Failed to connect. Check ESP32 and WiFi.');

        // Reset status after 3 seconds
        Timer(Duration(seconds: 3), () {
          if (mounted && !_isConnected) {
            setState(() {
              _connectionStatus = 'Disconnected';
            });
          }
        });
      }
    }
  }

  void _startStatusUpdates() {
    _statusTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
      if (_isConnected) {
        final status = await ESP32Service.getStatus();
        if (status != null && mounted) {
          setState(() {
            _batteryLevel = status['battery']?.toDouble() ?? _batteryLevel;
            _connectedClients = status['connectedClients'] ?? 0;

            if (_batteryLevel <= 20) {
              _batteryAnimationController.forward();
            } else {
              _batteryAnimationController.reverse();
            }
          });
        }
      }
    });
  }

  double _getSpeedMultiplier() {
    switch (_selectedSpeedMode) {
      case SpeedMode.low:
        return 0.3;
      case SpeedMode.mid:
        return 0.6;
      case SpeedMode.high:
        return 1.0;
    }
  }

  void _updateCarControl() async {
    final totalSpeed = math.sqrt((_joystickX * _joystickX) + (_joystickY * _joystickY));
    final adjustedSpeed = totalSpeed * _getSpeedMultiplier();

    String direction = 'STOP';

    // Only allow basic 4-direction movement (no diagonals)
    if (totalSpeed > 15) { // Increased threshold to make direction detection more stable
      // Determine primary axis and direction
      if (_joystickY.abs() > _joystickX.abs()) {
        // Y-axis dominates
        if (_joystickY < 0) {
          direction = 'FORWARD';
        } else {
          direction = 'BACKWARD';
        }
      } else {
        // X-axis dominates
        if (_joystickX > 0) {
          direction = 'RIGHT';
        } else {
          direction = 'LEFT';
        }
      }
    }

    setState(() {
      _currentDirection = direction;
    });

    _carControlsBox?.add(CarControlData(direction, adjustedSpeed, DateTime.now()));

    _speedAnimationController.forward().then((_) {
      _speedAnimationController.reverse();
    });

    // Send command to ESP32
    if (_isConnected) {
      // For basic movements, send appropriate values
      double sendX = 0.0;
      double sendY = 0.0;

      switch (direction) {
        case 'FORWARD':
          sendY = -50.0; // Negative for forward
          break;
        case 'BACKWARD':
          sendY = 50.0;  // Positive for backward
          break;
        case 'LEFT':
          sendX = -50.0; // Negative for left
          break;
        case 'RIGHT':
          sendX = 50.0;  // Positive for right
          break;
        default:
          sendX = 0.0;
          sendY = 0.0;
      }

      await ESP32Service.sendControl(sendX, sendY, _getSpeedMultiplier(), direction);

      if (adjustedSpeed > 20) {
        HapticFeedback.lightImpact();
      }
    }

    print('🚗 Command: $direction | Speed: ${adjustedSpeed.toInt()}% | Mode: ${_selectedSpeedMode.name}');
  }

  void _handleJoystick(Offset localPosition, Size joystickSize) {
    if (!_isConnected) return;

    final center = Offset(joystickSize.width / 2, joystickSize.height / 2);
    final offset = localPosition - center;
    final maxDistance = joystickSize.width / 2 - 20;

    final distance = math.sqrt(offset.dx * offset.dx + offset.dy * offset.dy);
    final clampedDistance = math.min(distance, maxDistance);

    Offset clampedOffset = Offset.zero;
    if (distance > 0) {
      clampedOffset = offset * (clampedDistance / distance);
    }

    setState(() {
      _joystickPosition = clampedOffset;
      _isDraggingJoystick = true;
      _joystickX = (clampedOffset.dx / maxDistance) * 100;
      _joystickY = (clampedOffset.dy / maxDistance) * 100;
    });

    _updateCarControl();
  }

  void _stopJoystick() {
    setState(() {
      _joystickPosition = Offset.zero;
      _isDraggingJoystick = false;
      _joystickX = 0.0;
      _joystickY = 0.0;
    });
    _updateCarControl();
  }

  void _stopCar() {
    _stopJoystick();
  }

  void _showMessage(String message) {
    if (mounted) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text('RC Controller'),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              child: Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  // Responsive helper methods
  double _getScaleFactor(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final baseWidth = 800.0;
    return math.min(size.width / baseWidth, 1.2);
  }

  bool _isSmallScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width < 750 || size.height < 400;
  }

  bool _isVerySmallScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width < 650 || size.height < 350;
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleFactor = _getScaleFactor(context);
        final isSmall = _isSmallScreen(context);
        final isVerySmall = _isVerySmallScreen(context);

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: (12 * scaleFactor).clamp(8.0, 20.0),
            vertical: (8 * scaleFactor).clamp(4.0, 12.0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: isVerySmall ? 3 : 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'ESP32 RC Controller',
                        style: TextStyle(
                          fontSize: isVerySmall ? 16 : isSmall ? 20 : (26 * scaleFactor).clamp(16.0, 30.0),
                          fontWeight: FontWeight.bold,
                          color: CupertinoColors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    SizedBox(height: (2 * scaleFactor).clamp(1.0, 4.0)), // Reduced height
                    AnimatedBuilder(
                      animation: _connectionAnimation,
                      builder: (context, child) {
                        return Row(
                          children: [
                            Icon(
                              CupertinoIcons.wifi,
                              size: (14 * scaleFactor).clamp(10.0, 18.0), // Slightly reduced icon size
                              color: _isConnected
                                  ? CupertinoColors.systemGreen
                                  : CupertinoColors.systemRed.withOpacity(_connectionAnimation.value * 0.8 + 0.2),
                            ),
                            SizedBox(width: (6 * scaleFactor).clamp(3.0, 8.0)), // Reduced width
                            Flexible(
                              child: Container(
                                constraints: BoxConstraints(
                                  maxHeight: (20 * scaleFactor).clamp(14.0, 24.0), // Add height constraint
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _isConnected && _connectedClients > 0
                                        ? '$_connectionStatus (${_connectedClients})'
                                        : _connectionStatus,
                                    style: TextStyle(
                                      color: _isConnected ? CupertinoColors.systemGreen : CupertinoColors.systemGrey,
                                      fontSize: isVerySmall ? 10 : isSmall ? 12 : (14 * scaleFactor).clamp(10.0, 16.0), // Reduced font size
                                      fontWeight: _isConnected ? FontWeight.w600 : FontWeight.normal,
                                      height: 1.0, // Add line height control
                                    ),
                                    maxLines: 1, // Ensure single line
                                    overflow: TextOverflow.ellipsis, // Handle overflow gracefully
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(width: (8 * scaleFactor).clamp(4.0, 12.0)),
              Flexible(
                child: CupertinoButton(
                  onPressed: _toggleConnection,
                  padding: EdgeInsets.symmetric(
                    horizontal: (16 * scaleFactor).clamp(8.0, 20.0),
                    vertical: (6 * scaleFactor).clamp(4.0, 8.0),
                  ),
                  color: _isConnected ? const Color(0xFF333333) : CupertinoColors.activeBlue,
                  borderRadius: BorderRadius.circular((16 * scaleFactor).clamp(12.0, 20.0)),
                  child: FittedBox(
                    child: Text(
                      _isConnected ? 'Disconnect' : 'Connect',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: isVerySmall ? 12 : isSmall ? 14 : (16 * scaleFactor).clamp(12.0, 18.0),
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleFactor = _getScaleFactor(context);
        final isSmall = _isSmallScreen(context);
        final isVerySmall = _isVerySmallScreen(context);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: (12 * scaleFactor).clamp(8.0, 20.0)),
          child: Row(
            children: [
              _buildStatusCard(
                icon: _batteryLevel > 75 ? CupertinoIcons.battery_full :
                _batteryLevel > 50 ? CupertinoIcons.battery_75_percent :
                _batteryLevel > 25 ? CupertinoIcons.battery_25_percent :
                CupertinoIcons.battery_0,
                iconColor: _batteryLevel > 20
                    ? CupertinoColors.systemGreen
                    : _batteryColorAnimation.value ?? CupertinoColors.systemRed,
                value: '${_batteryLevel.toInt()}%',
                label: 'Battery',
                scaleFactor: scaleFactor,
                isSmall: isSmall,
                isVerySmall: isVerySmall,
                animation: _batteryAnimationController,
                animateIcon: true,
              ),
              SizedBox(width: (8 * scaleFactor).clamp(4.0, 12.0)),
              _buildStatusCard(
                icon: CupertinoIcons.speedometer,
                iconColor: CupertinoColors.activeBlue,
                value: '${(math.sqrt(_joystickX * _joystickX + _joystickY * _joystickY) * _getSpeedMultiplier()).toInt()}%',
                label: 'Speed',
                scaleFactor: scaleFactor,
                isSmall: isSmall,
                isVerySmall: isVerySmall,
                animation: _speedAnimationController,
                animateIcon: true,
              ),
              SizedBox(width: (8 * scaleFactor).clamp(4.0, 12.0)),
              _buildStatusCard(
                icon: _getDirectionIcon(),
                iconColor: _currentDirection == 'STOP' ? CupertinoColors.systemRed : CupertinoColors.systemOrange,
                value: _getDirectionText(),
                label: 'Direction',
                scaleFactor: scaleFactor,
                isSmall: isSmall,
                isVerySmall: isVerySmall,
                animateIcon: false,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required double scaleFactor,
    required bool isSmall,
    required bool isVerySmall,
    AnimationController? animation,
    bool animateIcon = false,
  }) {
    return Expanded(
      child: AnimatedBuilder(
        animation: animation ?? AlwaysStoppedAnimation(1.0),
        builder: (context, child) {
          double scale = 1.0;
          if (animateIcon && animation != null) {
            scale = 1.0 + (animation.value * 0.1);
          }
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: (8 * scaleFactor).clamp(4.0, 16.0),
              vertical: (8 * scaleFactor).clamp(6.0, 14.0),
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular((12 * scaleFactor).clamp(8.0, 16.0)),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
              border: Border.all(
                color: CupertinoColors.systemGrey5.darkColor.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: scale,
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: isVerySmall ? 18 : isSmall ? 22 : (28 * scaleFactor).clamp(18.0, 32.0),
                  ),
                ),
                SizedBox(height: (2 * scaleFactor).clamp(1.0, 6.0)),
                FittedBox(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: isVerySmall ? 11 : isSmall ? 13 : (16 * scaleFactor).clamp(11.0, 18.0),
                      fontWeight: FontWeight.bold,
                      color: CupertinoColors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                FittedBox(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: isVerySmall ? 8 : isSmall ? 10 : (12 * scaleFactor).clamp(8.0, 14.0),
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _getDirectionIcon() {
    switch (_currentDirection) {
      case 'FORWARD':
        return CupertinoIcons.arrow_up;
      case 'BACKWARD':
        return CupertinoIcons.arrow_down;
      case 'LEFT':
        return CupertinoIcons.arrow_left;
      case 'RIGHT':
        return CupertinoIcons.arrow_right;
      default:
        return CupertinoIcons.stop_fill;
    }
  }

  String _getDirectionText() {
    return _currentDirection;
  }

  Widget _buildJoystick() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleFactor = _getScaleFactor(context);
        final isSmall = _isSmallScreen(context);
        final isVerySmall = _isVerySmallScreen(context);

        double joystickSize;
        if (isVerySmall) {
          joystickSize = math.min(constraints.maxWidth * 0.5, constraints.maxHeight * 0.7);
          joystickSize = math.min(joystickSize, 120);
        } else if (isSmall) {
          joystickSize = math.min(constraints.maxWidth * 0.6, constraints.maxHeight * 0.8);
          joystickSize = math.min(joystickSize, 150);
        } else {
          joystickSize = math.min(constraints.maxWidth * 0.7, constraints.maxHeight * 0.9);
          joystickSize = math.min(joystickSize, 200);
        }

        final knobSize = joystickSize * 0.35;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              child: Text(
                'Control',
                style: TextStyle(
                  fontSize: isVerySmall ? 14 : isSmall ? 16 : (18 * scaleFactor).clamp(14.0, 20.0),
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.white,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            SizedBox(height: (6 * scaleFactor).clamp(4.0, 10.0)),
            Container(
              width: joystickSize,
              height: joystickSize,
              child: GestureDetector(
                onPanStart: (details) {
                  if (!_isConnected) return;
                  HapticFeedback.lightImpact();
                  _handleJoystick(details.localPosition, Size(joystickSize, joystickSize));
                },
                onPanUpdate: (details) {
                  if (!_isConnected) return;
                  _handleJoystick(details.localPosition, Size(joystickSize, joystickSize));
                },
                onPanEnd: (details) {
                  HapticFeedback.lightImpact();
                  _stopJoystick();
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(joystickSize / 2),
                    color: const Color(0xFF2A2A2A),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF2A2A2A),
                        const Color(0xFF1A1A1A),
                      ],
                    ),
                    border: Border.all(
                      color: CupertinoColors.systemGrey5.darkColor.withOpacity(0.6),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: CupertinoColors.black.withOpacity(0.5),
                        blurRadius: 15,
                        spreadRadius: 2,
                        offset: Offset(0, 8),
                      ),
                      BoxShadow(
                        color: CupertinoColors.white.withOpacity(0.05),
                        blurRadius: 5,
                        spreadRadius: -2,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Cross-hair guides (+ shape for 4 directions)
                      Center(
                        child: Container(
                          width: 1,
                          height: joystickSize * 0.8,
                          color: CupertinoColors.systemGrey4.withOpacity(0.3),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: joystickSize * 0.8,
                          height: 1,
                          color: CupertinoColors.systemGrey4.withOpacity(0.3),
                        ),
                      ),
                      // Joystick knob
                      AnimatedPositioned(
                        duration: Duration(milliseconds: _isDraggingJoystick ? 0 : 250),
                        curve: Curves.easeOutCubic,
                        left: joystickSize / 2 + _joystickPosition.dx - knobSize / 2,
                        top: joystickSize / 2 + _joystickPosition.dy - knobSize / 2,
                        child: Container(
                          width: knobSize,
                          height: knobSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isConnected
                                ? ((_joystickX.abs() + _joystickY.abs()) > 10 ? CupertinoColors.activeBlue : CupertinoColors.systemGrey2)
                                : CupertinoColors.systemGrey,
                            gradient: RadialGradient(
                              colors: [
                                _isConnected
                                    ? ((_joystickX.abs() + _joystickY.abs()) > 10 ? CupertinoColors.systemCyan : CupertinoColors.systemGrey2)
                                    : CupertinoColors.systemGrey,
                                _isConnected
                                    ? ((_joystickX.abs() + _joystickY.abs()) > 10 ? CupertinoColors.activeBlue : CupertinoColors.systemGrey3)
                                    : CupertinoColors.systemGrey4,
                              ],
                              stops: [0.0, 1.0],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: CupertinoColors.black.withOpacity(0.6),
                                blurRadius: 10,
                                offset: Offset(0, 5),
                              ),
                              if (_isDraggingJoystick && _isConnected)
                                BoxShadow(
                                  color: CupertinoColors.activeBlue.withOpacity(0.5),
                                  blurRadius: 15,
                                  spreadRadius: 3,
                                ),
                            ],
                            border: Border.all(
                              color: CupertinoColors.white.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: (4 * scaleFactor).clamp(2.0, 8.0)),
          ],
        );
      },
    );
  }

  Widget _buildSpeedModeButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleFactor = _getScaleFactor(context);
        final isSmall = _isSmallScreen(context);
        final isVerySmall = _isVerySmallScreen(context);

        double buttonSize;
        if (isVerySmall) {
          buttonSize = math.min(constraints.maxWidth * 0.2, constraints.maxHeight * 0.25);
          buttonSize = math.min(buttonSize, 50);
        } else if (isSmall) {
          buttonSize = math.min(constraints.maxWidth * 0.25, constraints.maxHeight * 0.3);
          buttonSize = math.min(buttonSize, 60);
        } else {
          buttonSize = math.min(constraints.maxWidth * 0.3, constraints.maxHeight * 0.35);
          buttonSize = math.min(buttonSize, 80);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              child: Text(
                'Speed Mode',
                style: TextStyle(
                  fontSize: isVerySmall ? 14 : isSmall ? 16 : (18 * scaleFactor).clamp(14.0, 20.0),
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.white,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            SizedBox(height: (12 * scaleFactor).clamp(8.0, 16.0)),

            // Triangle Formation
            Column(
              children: [
                // Top - MID Speed Button
                _buildSpeedModeButton(
                  mode: SpeedMode.mid,
                  icon: CupertinoIcons.tortoise_fill,
                  label: 'LOW',
                  color: CupertinoColors.systemOrange,
                  size: buttonSize,
                  scaleFactor: scaleFactor,
                  isSmall: isSmall,
                  isVerySmall: isVerySmall,
                ),

                SizedBox(height: (12 * scaleFactor).clamp(8.0, 16.0)),

                // Bottom Row - LOW and HIGH Speed Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Low Speed Button
                    _buildSpeedModeButton(
                      mode: SpeedMode.low,
                      icon: CupertinoIcons.stop_circle,
                      label: 'NEUTRAL',
                      color: CupertinoColors.systemGreen,
                      size: buttonSize,
                      scaleFactor: scaleFactor,
                      isSmall: isSmall,
                      isVerySmall: isVerySmall,
                    ),

                    SizedBox(width: (12 * scaleFactor).clamp(8.0, 20.0)),

                    // High Speed Button
                    _buildSpeedModeButton(
                      mode: SpeedMode.high,
                      icon: CupertinoIcons.flame_fill,
                      label: 'HIGH',
                      color: CupertinoColors.systemRed,
                      size: buttonSize,
                      scaleFactor: scaleFactor,
                      isSmall: isSmall,
                      isVerySmall: isVerySmall,
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSpeedModeButton({
    required SpeedMode mode,
    required IconData icon,
    required String label,
    required Color color,
    required double size,
    required double scaleFactor,
    required bool isSmall,
    required bool isVerySmall,
  }) {
    final isSelected = _selectedSpeedMode == mode;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedSpeedMode = mode;
        });
        HapticFeedback.selectionClick();
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? color.withOpacity(0.2) : const Color(0xFF2A2A2A),
          border: Border.all(
            color: isSelected ? color : CupertinoColors.systemGrey5.darkColor.withOpacity(0.5),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
            if (isSelected)
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 15,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : CupertinoColors.systemGrey,
              size: isVerySmall ? 16 : isSmall ? 20 : (26 * scaleFactor).clamp(16.0, 30.0),
            ),
            SizedBox(height: (2 * scaleFactor).clamp(1.0, 3.0)),
            FittedBox(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isVerySmall ? 7 : isSmall ? 9 : (11 * scaleFactor).clamp(7.0, 13.0),
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : CupertinoColors.systemGrey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;
            final isNarrowHeight = screenHeight < 380;

            return SizedBox(
              height: screenHeight,
              child: Column(
                children: [
                  // Header with constrained height
                  SizedBox(
                    height: isNarrowHeight ? 60 : 80,
                    child: _buildHeader(),
                  ),

                  // Status cards with constrained height
                  SizedBox(
                    height: isNarrowHeight ? 70 : 85,
                    child: _buildStatusCards(),
                  ),

                  SizedBox(height: isNarrowHeight ? 8 : 16),

                  // The main interactive area (joystick and speed buttons) - takes remaining space
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: _buildJoystick(),
                          ),
                          SizedBox(width: 12),
                          Flexible(
                            child: _buildSpeedModeButtons(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom padding to prevent overflow
                  SizedBox(height: 8),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// Custom AnimatedPositioned widget for smooth joystick knob movement
class AnimatedPositioned extends StatefulWidget {
  final Duration duration;
  final Curve curve;
  final double left;
  final double top;
  final Widget child;

  const AnimatedPositioned({
    Key? key,
    required this.duration,
    this.curve = Curves.linear,
    required this.left,
    required this.top,
    required this.child,
  }) : super(key: key);

  @override
  _AnimatedPositionedState createState() => _AnimatedPositionedState();
}

class _AnimatedPositionedState extends State<AnimatedPositioned>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;
  Offset _currentPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _animation = Tween<Offset>(
      begin: Offset(widget.left, widget.top),
      end: Offset(widget.left, widget.top),
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));
    _currentPosition = Offset(widget.left, widget.top);
  }

  @override
  void didUpdateWidget(AnimatedPositioned oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.left != widget.left || oldWidget.top != widget.top || oldWidget.duration != widget.duration || oldWidget.curve != widget.curve) {
      _controller.duration = widget.duration;
      _animation = Tween<Offset>(
        begin: _currentPosition,
        end: Offset(widget.left, widget.top),
      ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        _currentPosition = _animation.value;
        return Positioned(
          left: _currentPosition.dx,
          top: _currentPosition.dy,
          child: widget.child,
        );
      },
    );
  }
}