// ignore_for_file: avoid_print, unused_catch_clause, unused_local_variable, unused_field, prefer_typing_uninitialized_variables, non_constant_identifier_names

import 'dart:convert';
import 'dart:math';
import 'package:bs58/bs58.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uni_links/uni_links.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:pinenacl/x25519.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final sessionConnectPrivateKey = PrivateKey.generate();
  late final encodedSessionPrivateKey;
  String? dapp_encryption_public_key;
  String? dapp_public_key;
  String? session;
  bool _initialURILinkHandled = false;

  StreamSubscription? _streamSubscription;
  @override
  void initState() {
    _initURIHandler();
    _incomingLinkHandler();
    encodedSessionPrivateKey = base58.encode(
      sessionConnectPrivateKey.toUint8List(),
    );
    super.initState();
  }

  Future<void> _initURIHandler() async {
    // 1
    if (!_initialURILinkHandled) {
      _initialURILinkHandled = true;
      // 2
      print("Invoked _initURIHandler");
      try {
        // 3
        final initialURI = await getInitialUri();
        // 4
        if (initialURI != null) {
          debugPrint("Initial URI received $initialURI");
          if (!mounted) {
            return;
          }
        } else {
          debugPrint("Null Initial URI received");
        }
      } on PlatformException {
        // 5
        debugPrint("Failed to receive initial uri");
      } on FormatException catch (err) {
        // 6
        if (!mounted) {
          return;
        }
        debugPrint('Malformed Initial URI received');
      }
    }
  }

  void _incomingLinkHandler() {
    // 1
    if (!kIsWeb) {
      // 2
      _streamSubscription = uriLinkStream.listen((Uri? uri) {
        if (!mounted) {
          return;
        }
        if (uri == null) {
          return;
        }
        debugPrint('Received URI: $uri');
        if (uri.path.contains("/onConnect")) {
          handleOnConnect(uri);
        }

        if (uri.path.contains("/onSign")) {
          handleOnSign(uri);
        }

        print(uri.path);
        // 3
      }, onError: (Object err) {
        if (!mounted) {
          return;
        }
        debugPrint('Error occurred: $err');
      });
    }
  }

  void handleOnSign(Uri uri) async {
    print(uri.queryParameters);
  }

  void handleOnConnect(Uri uri) async {
    dapp_encryption_public_key =
        uri.queryParameters["phantom_encryption_public_key"];
    if (dapp_encryption_public_key == null) {
      return;
    }
    var box = Box(
      myPrivateKey: PrivateKey(base58.decode(encodedSessionPrivateKey)),
      theirPublicKey: PublicKey(base58.decode(dapp_encryption_public_key!)),
    );
    final encodedData = uri.queryParameters["data"];
    final encodedNonce = uri.queryParameters["nonce"];
    if (encodedNonce == null || encodedData == null) {
      return;
    }
    try {
      var decryptedMessageBytes = box.decrypt(
        ByteList.fromList(base58.decode(encodedData)),
        nonce: base58.decode(encodedNonce),
      );

      var decryptedMessageString = String.fromCharCodes(decryptedMessageBytes);

      var decodedPayload = jsonDecode(decryptedMessageString);
      session = decodedPayload["session"];
      setState(() {
        dapp_public_key = decodedPayload["public_key"];
      });

      print(decodedPayload);
      print("session is $session");
      print("dapp_encryption_public_key is $dapp_encryption_public_key");
    } catch (e) {
      print(e);
    }
  }

  void _connect() {
    Map<String, dynamic> queryParameters = {
      "dapp_encryption_public_key":
          base58.encode(Uint8List.fromList(sessionConnectPrivateKey.publicKey)),
      "cluster": "devnet",
      "app_url": "https://phantom.app",
      "redirect_link": "http://ragfan.page.link/onConnect",
    };

    final url = Uri(
      scheme: "https",
      host: "phantom.app",
      path: "/ul/v1/connect",
      queryParameters: queryParameters,
    );

    launchUrl(
      url,
      mode: LaunchMode.externalNonBrowserApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            dapp_public_key == null
                ? ElevatedButton(
                    onPressed: _connect,
                    child: const Text("Connect Wallet"),
                  )
                : Center(
                    child:
                        Text(dapp_public_key ?? "Couldn't get wallet address"),
                  )
            // ElevatedButton(
            //   onPressed: signMessage,
            //   child: const Text("Sign Message"),
            // )
          ],
        ),
      ),
    );
  }

  void signMessage() {
    const msg = "Dummy Message";
    List<int> list = msg.codeUnits;
    Uint8List bytes = Uint8List.fromList(list);
    var payload = {"session": session, "message": base58.encode(bytes)};

    var payS = payload.toString();
    List<int> listPay = payS.codeUnits;
    Uint8List bytesPay = Uint8List.fromList(list);
    var box = Box(
      myPrivateKey: PrivateKey(base58.decode(encodedSessionPrivateKey)),
      theirPublicKey: PublicKey(base58.decode(dapp_encryption_public_key!)),
    );
    var nonce = randomUint8List(24);
    var encryptedPayload = box.encrypt(bytesPay, nonce: nonce);
    Map<String, dynamic> queryParameters = {
      "dapp_encryption_public_key":
          base58.encode(Uint8List.fromList(sessionConnectPrivateKey.publicKey)),
      "nonce": base58.encode(nonce),
      "payload": base58.encode(encryptedPayload.asTypedList),
      "redirect_link": "http://ragfan.page.link/onSign",
    };
    final url = Uri(
      scheme: "https",
      host: "phantom.app",
      path: "/ul/v1/signTransaction",
      queryParameters: queryParameters,
    );

    launchUrl(
      url,
      mode: LaunchMode.externalNonBrowserApplication,
    );
  }

  Uint8List randomUint8List(int length) {
    assert(length > 0);

    final random = Random();
    final ret = Uint8List(length);

    for (var i = 0; i < length; i++) {
      ret[i] = random.nextInt(256);
    }

    return ret;
  }
}
