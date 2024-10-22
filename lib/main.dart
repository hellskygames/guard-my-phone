import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:local_auth/local_auth.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guard My Phone',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSecurityActive = false;
  bool _isNfcDetected = false;
  bool _isAlarmActive = false;
  Timer? _verificationTimer;
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  final LocalAuthentication _localAuth = LocalAuthentication();

  static const platform = MethodChannel('com.smarttrash.guardmyphone/lock_state');

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _checkNfcAvailability();
  }

  @override
  void dispose() {
    _verificationTimer?.cancel();
    _audioPlayer.dispose();
    NfcManager.instance.stopSession();
    super.dispose();
  }

  void _checkNfcAvailability() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable && mounted) {
      _showNfcUnavailableDialog();
    }
  }

  void _showNfcUnavailableDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text('NFC no está disponible en este dispositivo.'),
        actions: <Widget>[
          TextButton(
            child: Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _toggleSecurity() async {
    if (!_isSecurityActive) {
      _startSecurityProcess();
    } else {
      // Requerir autenticación antes de desactivar
      bool isAuthenticated = false;
      try {
        isAuthenticated = await _localAuth.authenticate(
          localizedReason: 'Por favor, autentíquese para desactivar la seguridad',
          options: const AuthenticationOptions(biometricOnly: true),
        );
      } catch (e) {
        print("Error en autenticación biométrica: $e");
      }

      if (isAuthenticated) {
        _stopSecurityProcess();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Autenticación necesaria para desactivar la seguridad'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _startSecurityProcess() {
    setState(() {
      _isSecurityActive = true;
      _isNfcDetected = false;
      _isAlarmActive = false;
    });

    _enableNFC();
    _startNfcDetection();

    // Tiempo inicial para colocar el NFC
    Future.delayed(Duration(seconds: 10), () {
      if (_isSecurityActive && !_isNfcDetected && mounted) {
        _authenticateUser(); // Pedir autenticación inmediatamente si no hay NFC
      } else if (_isSecurityActive && _isNfcDetected && mounted) {
        _startPeriodicVerification(); // Iniciar ciclo si hay NFC
      }
    });
  }

  void _stopSecurityProcess() {
    setState(() {
      _isSecurityActive = false;
      _isNfcDetected = false;
      _isAlarmActive = false;
    });
    _verificationTimer?.cancel();
    _verificationTimer = null;
    _stopAlertSound();
    _disableNFC();
    NfcManager.instance.stopSession();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sistema de seguridad desactivado'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _enableNFC() async {
    try {
      await platform.invokeMethod('enableNFCForeground');
    } catch (e) {
      print("Error enabling NFC: $e");
    }
  }

  Future<void> _disableNFC() async {
    try {
      await platform.invokeMethod('disableNFCForeground');
    } catch (e) {
      print("Error disabling NFC: $e");
    }
  }

  void _startNfcDetection() {
    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      if (mounted) {
        setState(() {
          _isNfcDetected = true;
        });

        if (_isAlarmActive) {
          _stopAlertSound();
          setState(() {
            _isAlarmActive = false;
          });
          _startPeriodicVerification(); // Reiniciar ciclo después de detener alarma
        } else if (_verificationTimer == null || !_verificationTimer!.isActive) {
          _startPeriodicVerification(); // Iniciar ciclo si no está activo
        }
      }
    });
  }

  void _startPeriodicVerification() {
    _verificationTimer?.cancel();
    _verificationTimer = Timer.periodic(Duration(seconds: 3), (timer) async {
      if (!_isSecurityActive) {
        timer.cancel();
        return;
      }

      setState(() {
        _isNfcDetected = false;
      });

      await Future.delayed(Duration(milliseconds: 500));

      if (!mounted) return;

      NfcManager.instance.stopSession();
      _startNfcDetection();

      if (!_isNfcDetected) {
        print('NFC no detectado, verificando autenticación');
        await _authenticateUser();
      }
    });
  }

  Future<void> _authenticateUser() async {
    if (!_isSecurityActive || !mounted) return;

    bool isAuthenticated = false;

    try {
      isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Por favor, autentíquese con su huella',
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } catch (e) {
      print("Error en autenticación biométrica: $e");
    }

    if (!mounted) return;

    if (isAuthenticated) {
      _stopSecurityProcess();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Seguridad desactivada correctamente'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      if (_isSecurityActive && !_isNfcDetected && !_isAlarmActive) {
        await Future.delayed(Duration(seconds: 5));
        if (_isSecurityActive && !_isNfcDetected && !_isAlarmActive && mounted) {
          setState(() {
            _isAlarmActive = true;
          });
          await _startAlertSound();
        }
      }
    }
  }

  Future<void> _startAlertSound() async {
    if (!_isPlaying) {
      _isPlaying = true;
      try {
        await _audioPlayer.play(AssetSource('audio/alarma.mp3'));
        _audioPlayer.setReleaseMode(ReleaseMode.loop);
        print('Iniciando sonido de alarma');
      } catch (e) {
        print('Error al reproducir sonido: $e');
        _isPlaying = false;
        setState(() {
          _isAlarmActive = false;
        });
      }
    }
  }

  void _stopAlertSound() {
    _audioPlayer.stop();
    _isPlaying = false;
    setState(() {
      _isAlarmActive = false;
    });
    print('Deteniendo sonido de alarma');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('   Guard my phone'),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue, Colors.lightBlueAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Text(
                'Opciones',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.person),
              title: Text('Perfil'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('Configuración'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Icon(Icons.info),
              title: Text('Acerca de'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),git init
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            GestureDetector(
              onTap: _toggleSecurity,
              child: AnimatedContainer(
                duration: Duration(milliseconds: 300),
                width: _isSecurityActive ? 165 : 150,
                height: _isSecurityActive ? 165 : 150,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _isSecurityActive
                        ? [Colors.red, Colors.redAccent]
                        : [Colors.blue, Colors.lightBlueAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _isSecurityActive
                          ? Colors.red.withOpacity(0.6)
                          : Colors.blue.withOpacity(0.4),
                      blurRadius: 15,
                      spreadRadius: 8,
                    ),
                  ],
                  image: DecorationImage(
                    image: AssetImage('assets/imagenes/escudo.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            SizedBox(height: 30),
            Text(
              _isSecurityActive
                  ? 'Seguridad Activada'
                  : 'Presiona el escudo para activar la seguridad',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _isSecurityActive ? Colors.redAccent : Colors.blueAccent,
                shadows: [
                  Shadow(
                    blurRadius: 10.0,
                    color: Colors.black.withOpacity(0.2),
                    offset: Offset(3, 3),
                  ),
                ],
              ),
            ),



            if (_isSecurityActive)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _isAlarmActive
                      ? '¡Alarma Activa!'
                      : _isNfcDetected
                      ? 'NFC Detectado'
                      : 'Esperando NFC...',
                  style: TextStyle(
                    fontSize: 14,
                    color: _isAlarmActive
                        ? Colors.red
                        : _isNfcDetected
                        ? Colors.green
                        : Colors.orange,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}