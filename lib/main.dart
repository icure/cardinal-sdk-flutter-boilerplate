import 'dart:math';

import 'package:cardinal_sdk/auth/authentication_process_telecom_type.dart';
import 'package:cardinal_sdk/auth/captcha_options.dart';
import 'package:cardinal_sdk/cardinal_sdk.dart';
import 'package:cardinal_sdk/filters/patient_filters.dart';
import 'package:cardinal_sdk/model/patient.dart';
import 'package:cardinal_sdk/options/storage_options.dart';
import 'package:cardinal_sdk/subscription/entity_subscription.dart';
import 'package:cardinal_sdk/subscription/entity_subscription_event.dart';
import 'package:cardinal_sdk/subscription/subscription_event_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: StartAuthScreen(),
    );
  }
}

// Screen 1
class StartAuthScreen extends StatefulWidget {
  @override
  _StartAuthScreenState createState() => _StartAuthScreenState();
}

class _StartAuthScreenState extends State<StartAuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isButtonDisabled = false;
  String? _errorMessage;
  void _startAuth() async {
    setState(() {
      _isButtonDisabled = true;
      _errorMessage = null;
    });
    try {
      final email = _emailController.text;
      final authStep = await CardinalSdk.initializeWithProcess(
        null,
        "https://api.icure.cloud",
        "https://msg-gw.icure.cloud",
        throw UnimplementedError("Fill this with the specId from the cockpit"),
        throw UnimplementedError("Fill this with the a user login/registration process for your database"),
        AuthenticationProcessTelecomType.email,
        email,
        CaptchaOptions.KerberusDelegated(),
        StorageOptions.PlatformDefault,
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CompleteAuthScreen(authStep: authStep, email: email),
        ),
      ).then((_) {
        setState(() {
          _isButtonDisabled = false;
        });
      });
    } catch (e) {
      setState(() {
        _errorMessage = e is PlatformException ? e.message : e.toString();
        _isButtonDisabled = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login / register')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            if (_errorMessage != null) Container(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                overflow: TextOverflow.ellipsis,
                maxLines: 20,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isButtonDisabled ? null : _startAuth,
              child: const Text("Start auth"),
            ),
          ],
        ),
      ),
    );
  }
}

// Screen 2
class CompleteAuthScreen extends StatefulWidget {
  final AuthenticationWithProcessStep authStep;
  final String email;
  CompleteAuthScreen({
    required this.authStep,
    required this.email
  });

  @override
  _CompleteAuthScreenState createState() => _CompleteAuthScreenState();
}

class _CompleteAuthScreenState extends State<CompleteAuthScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isButtonDisabled = false;
  String? _errorMessage;

  void _continue() async {
    setState(() {
      _isButtonDisabled = true;
      _errorMessage = null;
    });
    try {
      final sdk = await widget.authStep.completeAuthentication(_codeController.text);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => TrySdkScreen(sdk: sdk, email: widget.email)),
      ).then((_) {
        setState(() {
          _isButtonDisabled = false;
        });
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isButtonDisabled = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Validate Login / Register')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('email: ${widget.email}'),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: "Validation Code"),
            ),
            if (_errorMessage != null) Container(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                overflow: TextOverflow.ellipsis,
                maxLines: 20,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isButtonDisabled ? null : _continue,
              child: const Text("Continue"),
            ),
          ],
        ),
      ),
    );
  }
}

class TrySdkScreen extends StatefulWidget {
  final CardinalSdk sdk;
  final String email;
  TrySdkScreen({required this.sdk, required this.email});

  @override
  _TrySdkScreen createState() => _TrySdkScreen();
}

class _TrySdkScreen extends State<TrySdkScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<String> _logMessages = [];
  bool _isButtonDisabled = false;
  EntitySubscription<Patient>? _subscription;


  void log(String msg) {
    setState(() {
      _logMessages.add(msg);
    });
    _scrollToBottom();
  }

  void createSamplePatient() async {
    setState(() {
      _isButtonDisabled = true;
    });
    final id = generateUuid();
    final createdPatient = await widget.sdk.patient.createPatient(
        await widget.sdk.patient.withEncryptionMetadata(
            DecryptedPatient(
                id,
                firstName: "John",
                lastName: id,
                note: "This will be encrypted"
            )
        )
    );
    log("Created patient ${createdPatient.firstName} ${createdPatient.lastName}");
    setState(() {
      _isButtonDisabled = false;
    });
  }

  void startSubscription() async {
    setState(() {
      _isButtonDisabled = true;
    });
    final subscription = await widget.sdk.patient.subscribeToEvents({SubscriptionEventType.create}, await PatientFilters.allPatientsForSelf());
    log("Subscription to created patients started");
    setState(() {
      _isButtonDisabled = false;
      _subscription = subscription;
    });
    while ((await subscription.getCloseReason()) == null) {
      final event = await subscription.waitForEvent(const Duration(minutes: 1));
      if (event is EntityNotification<EncryptedPatient>) {
        log("Subscription received event for creation of patient '${event.entity.firstName} ${event.entity.lastName}'");
      } else {
        log("Subscription received event $event");
      }
    }
    log("Subscription was closed ${await subscription.getCloseReason()}");
  }

  void closeSubscription() async {
    setState(() {
      _isButtonDisabled = true;
    });
    await _subscription!.close();
    log("Subscription closed");
    setState(() {
      _isButtonDisabled = false;
      _subscription = null;
    });
  }

  void getAllPatients() async {
    setState(() {
      _isButtonDisabled = true;
    });
    final pages = await widget.sdk.patient.tryAndRecover.filterPatientsBy(await PatientFilters.allPatientsForSelf());
    while (await pages.hasNext()) {
      final page = await pages.next(10);
      log("Got page of ${page.length} patients:\n${page.map((p) => "Patient '${p.firstName} ${p.lastName}' wasDecrypted=${p is DecryptedPatient}").join("\n")}");
    }
    setState(() {
      _isButtonDisabled = false;
    });
  }

  void clearLog() {
    setState(() {
      _logMessages.clear();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<bool> _showLogoutConfirmation() async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
            child: const Text('Yes'),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        await _showLogoutConfirmation();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Try SDK')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text("Logged in as ${widget.email}"),
              Wrap(
                  spacing: 10,
                  children: [
                    ElevatedButton(
                      onPressed: () => _isButtonDisabled ? null : createSamplePatient(),
                      child: const Text('Create sample patient'),
                    ),
                    ElevatedButton(
                      onPressed: () => _isButtonDisabled || _subscription != null ? null : startSubscription(),
                      child: const Text('Start subscription'),
                    ),
                    ElevatedButton(
                      onPressed: () => _isButtonDisabled || _subscription == null ? null : closeSubscription(),
                      child: const Text('Close subscription'),
                    ),
                    ElevatedButton(
                      onPressed: () => _isButtonDisabled ? null : getAllPatients(),
                      child: const Text('Get all patients'),
                    )
                  ]
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: clearLog,
                child: const Text('Clear Display'),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _logMessages.length,
                    itemBuilder: (context, index) {
                      return Text(_logMessages[index]);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String generateUuid() {
  final random = Random.secure();

  String generateHex(int count) {
    return List<int>.generate(count, (_) => random.nextInt(256))
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('');
  }

  String generateTimeLow() {
    return generateHex(4);
  }

  String generateTimeMid() {
    return generateHex(2);
  }

  String generateTimeHiAndVersion() {
    final timeHi = generateHex(2);
    final hiAndVersion = (int.parse(timeHi, radix: 16) & 0x0fff) | 0x4000;
    return hiAndVersion.toRadixString(16).padLeft(4, '0');
  }

  String generateClockSeqAndReserved() {
    final clockSeq = generateHex(2);
    final clockSeqRes = (int.parse(clockSeq, radix: 16) & 0x3fff) | 0x8000;
    return clockSeqRes.toRadixString(16).padLeft(4, '0');
  }

  String generateNode() {
    return generateHex(6);
  }

  return '${generateTimeLow()}-${generateTimeMid()}-${generateTimeHiAndVersion()}-${generateClockSeqAndReserved()}-${generateNode()}';
}
